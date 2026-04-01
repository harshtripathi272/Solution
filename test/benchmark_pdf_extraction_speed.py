"""
Benchmark PDF extraction speed and token volume using the current pipeline path.

What this measures (per URL):
1) PDF download time (same method used by unified extractor)
2) PDF text extraction time (same truncation behavior as current extractor)
3) Text volume and token count estimate

Usage examples:
    python ./test/benchmark_pdf_extraction_speed.py --url https://example.com/report.pdf
    python ./test/benchmark_pdf_extraction_speed.py --url https://a.pdf --url https://b.pdf --repeats 2
    python ./test/benchmark_pdf_extraction_speed.py --file ./test/pdf_urls.txt
"""

from __future__ import annotations

import argparse
import asyncio
import statistics
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

# Add backend to import path
sys.path.append(str(Path(__file__).resolve().parents[1] / "backend"))

from pypdf import PdfReader

from pipeline.processing.unified_extractor import nvidia_extractor


@dataclass
class RunResult:
    url: str
    run_index: int
    ok: bool
    error: str
    download_seconds: float
    parse_seconds: float
    total_seconds: float
    file_size_bytes: int
    total_pages: int
    parsed_pages: int
    text_chars: int
    text_words: int
    approx_tokens: int


def _approx_tokens_from_text(text: str) -> int:
    # Practical heuristic for English-like text used for quick ops benchmarking.
    # Roughly: 1 token ~= 0.75 words => tokens ~= words / 0.75
    words = len(text.split())
    return int(round(words / 0.75))


def _load_urls(args: argparse.Namespace) -> list[str]:
    urls: list[str] = []
    urls.extend(args.url or [])

    if args.file:
        p = Path(args.file)
        if not p.exists():
            raise FileNotFoundError(f"URL file not found: {p}")
        for line in p.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            urls.append(line)

    # De-duplicate while preserving order
    deduped: list[str] = []
    seen: set[str] = set()
    for u in urls:
        if u not in seen:
            deduped.append(u)
            seen.add(u)
    return deduped


async def _single_run(url: str, run_index: int) -> RunResult:
    t0 = time.perf_counter()
    try:
        d0 = time.perf_counter()
        buffer, _sha256 = await nvidia_extractor._download_pdf_to_memory(url)  # current pipeline method
        download_seconds = time.perf_counter() - d0

        pdf_bytes = buffer.getvalue()
        size_bytes = len(pdf_bytes)

        # Metadata (page count) for context.
        reader = PdfReader(buffer)
        total_pages = len(reader.pages)
        parsed_pages = min(total_pages, 10)  # extractor currently truncates at first 10 pages

        p0 = time.perf_counter()
        text = nvidia_extractor._extract_text_from_pdf(pdf_bytes)  # current pipeline method
        parse_seconds = time.perf_counter() - p0

        text_chars = len(text)
        text_words = len(text.split())
        approx_tokens = _approx_tokens_from_text(text)

        total_seconds = time.perf_counter() - t0
        return RunResult(
            url=url,
            run_index=run_index,
            ok=True,
            error="",
            download_seconds=download_seconds,
            parse_seconds=parse_seconds,
            total_seconds=total_seconds,
            file_size_bytes=size_bytes,
            total_pages=total_pages,
            parsed_pages=parsed_pages,
            text_chars=text_chars,
            text_words=text_words,
            approx_tokens=approx_tokens,
        )
    except Exception as exc:
        total_seconds = time.perf_counter() - t0
        return RunResult(
            url=url,
            run_index=run_index,
            ok=False,
            error=str(exc),
            download_seconds=0.0,
            parse_seconds=0.0,
            total_seconds=total_seconds,
            file_size_bytes=0,
            total_pages=0,
            parsed_pages=0,
            text_chars=0,
            text_words=0,
            approx_tokens=0,
        )


def _fmt_seconds(x: float) -> str:
    return f"{x:.3f}s"


def _print_run(res: RunResult) -> None:
    if not res.ok:
        print(f"[FAIL] run={res.run_index} url={res.url}")
        print(f"       error={res.error}")
        print(f"       total={_fmt_seconds(res.total_seconds)}")
        return

    kb = res.file_size_bytes / 1024
    mb = kb / 1024
    print(f"[OK] run={res.run_index} url={res.url}")
    print(
        "     "
        f"size={mb:.2f}MB "
        f"download={_fmt_seconds(res.download_seconds)} "
        f"parse={_fmt_seconds(res.parse_seconds)} "
        f"total={_fmt_seconds(res.total_seconds)}"
    )
    print(
        "     "
        f"pages_total={res.total_pages} pages_parsed={res.parsed_pages} "
        f"chars={res.text_chars} words={res.text_words} approx_tokens={res.approx_tokens}"
    )


def _print_summary(results: list[RunResult]) -> None:
    good = [r for r in results if r.ok]
    bad = [r for r in results if not r.ok]

    print("\n=== SUMMARY ===")
    print(f"runs_total={len(results)} success={len(good)} failed={len(bad)}")

    if not good:
        return

    dls = [r.download_seconds for r in good]
    prs = [r.parse_seconds for r in good]
    tots = [r.total_seconds for r in good]
    toks = [r.approx_tokens for r in good]

    print(
        "download: "
        f"mean={_fmt_seconds(statistics.mean(dls))} "
        f"p50={_fmt_seconds(statistics.median(dls))} "
        f"max={_fmt_seconds(max(dls))}"
    )
    print(
        "parse:    "
        f"mean={_fmt_seconds(statistics.mean(prs))} "
        f"p50={_fmt_seconds(statistics.median(prs))} "
        f"max={_fmt_seconds(max(prs))}"
    )
    print(
        "total:    "
        f"mean={_fmt_seconds(statistics.mean(tots))} "
        f"p50={_fmt_seconds(statistics.median(tots))} "
        f"max={_fmt_seconds(max(tots))}"
    )
    print(
        "tokens:   "
        f"mean={int(statistics.mean(toks))} "
        f"p50={int(statistics.median(toks))} "
        f"max={max(toks)}"
    )


async def main() -> None:
    parser = argparse.ArgumentParser(description="Benchmark PDF extraction speed and token size.")
    parser.add_argument("--url", action="append", help="PDF URL to benchmark (repeatable).")
    parser.add_argument("--file", type=str, help="Text file with one PDF URL per line.")
    parser.add_argument("--repeats", type=int, default=1, help="Number of runs per URL (default: 1).")
    args = parser.parse_args()

    urls = _load_urls(args)
    if not urls:
        parser.error("Provide at least one --url or --file with URLs.")

    repeats = max(1, args.repeats)

    print("Benchmarking current extraction path:")
    print("- download: nvidia_extractor._download_pdf_to_memory")
    print("- parse:    nvidia_extractor._extract_text_from_pdf")
    print("- token estimate: words / 0.75")
    print()

    results: list[RunResult] = []
    run_i = 0
    for u in urls:
        for _ in range(repeats):
            run_i += 1
            res = await _single_run(u, run_i)
            results.append(res)
            _print_run(res)

    _print_summary(results)


if __name__ == "__main__":
    asyncio.run(main())
