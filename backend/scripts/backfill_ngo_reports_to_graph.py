from __future__ import annotations

import argparse
import asyncio
import json
import logging
import os
from pathlib import Path
from typing import Any

from dotenv import load_dotenv

# Ensure imports work when this script is run directly:
#   python backend/scripts/backfill_ngo_reports_to_graph.py ...
BACKEND_ROOT = Path(__file__).resolve().parents[1]
PROJECT_ROOT = BACKEND_ROOT.parent
if str(BACKEND_ROOT) not in os.sys.path:
    os.sys.path.insert(0, str(BACKEND_ROOT))

from pipeline.ingestors.ngo_reports import NGOReportsIngestor
from pipeline.processing.community_graph import community_graph_service
from pipeline.processing.geohash import encode as geohash_encode
from pipeline.storage import firestore_store, neo4j_store
from severity_engine.acute_calculator import calculate_acute_severity
from severity_engine.chronic_calculator import calculate_chronic_severity
from severity_engine.composite_aggregator import aggregate_composite_urgency
from severity_engine.constants import CLASSIFICATION_TO_SEVERITY_LABEL


logger = logging.getLogger("backfill_ngo_reports_to_graph")


def _read_jsonl(path: Path, max_records: int = 0) -> list[dict[str, Any]]:
    records: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.lstrip("\ufeff").strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(obj, dict):
                records.append(obj)
            if max_records > 0 and len(records) >= max_records:
                break
    return records


def _classify(score: float) -> tuple[str, str]:
    if score < 0.35:
        return "Moderate", "48h"
    if score < 0.60:
        return "Severe", "24h"
    if score < 0.80:
        return "Critical", "12h"
    return "Extreme", "4h"


async def _build_severity_payload(event: Any) -> dict[str, Any]:
    """Compute an offline severity payload compatible with graph projection fields."""
    acute = float(calculate_acute_severity(event))
    chronic = float(calculate_chronic_severity(event))
    composite = float(aggregate_composite_urgency(acute, chronic, trend_bonus=0.0, gap_penalty=0.0))
    classification, response_time = _classify(composite)

    payload = {
        "severity_acute": round(acute, 4),
        "severity_chronic": round(chronic, 4),
        "composite_urgency": round(composite, 4),
        "classification": classification,
        "recommended_response_time": response_time,
        "reliability_score": round(float(getattr(event, "confidence_score", 0.6) or 0.6), 4),
    }

    severity_label = CLASSIFICATION_TO_SEVERITY_LABEL.get(classification, event.severity)
    event.severity = severity_label
    event.metadata = {
        **(event.metadata or {}),
        "severity_engine": payload,
    }
    return payload


async def backfill(
    input_path: Path,
    limit: int,
    dry_run: bool,
) -> tuple[int, int, int]:
    if not input_path.exists():
        raise FileNotFoundError(f"Input JSONL not found: {input_path}")

    records = _read_jsonl(input_path, max_records=limit)

    ingestor = NGOReportsIngestor(interval_seconds=3600, max_reports=max(1, limit or 1))

    processed = 0
    projected = 0
    skipped = 0

    for rec in records:
        event = ingestor._to_event(rec)
        if event is None:
            skipped += 1
            continue

        # Keep parity with unified pipeline annotations.
        event.source_tier = 2
        if not event.geohash:
            event.geohash = geohash_encode(event.location.latitude, event.location.longitude, precision=5)

        community_context = community_graph_service.resolve_community(event)
        if community_context:
            event.metadata = {
                **(event.metadata or {}),
                **community_context,
            }

        severity_payload = await _build_severity_payload(event)
        projection = community_graph_service.build_projection(event, severity_payload)
        if projection is None:
            skipped += 1
            processed += 1
            continue

        if dry_run:
            projected += 1
            processed += 1
            continue

        await neo4j_store.upsert_projection(projection)
        await firestore_store.upsert_community_projection(projection)
        projected += 1

        processed += 1

        if processed % 25 == 0:
            logger.info("Processed %d rows | projected=%d | skipped=%d", processed, projected, skipped)

    return processed, projected, skipped


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Backfill NGO scraped JSONL into community graph sinks (Neo4j + Firestore).",
    )
    parser.add_argument(
        "--input",
        default="backend/data/ngo_reports.jsonl",
        help="Path to scraped JSONL file (default: backend/data/ngo_reports.jsonl)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Max records to process (0 = all)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Build projections without writing to sinks",
    )
    return parser


async def _main_async(args: argparse.Namespace) -> int:
    input_path = Path(args.input)
    if not input_path.is_absolute():
        input_path = PROJECT_ROOT / input_path

    processed, projected, skipped = await backfill(
        input_path=input_path,
        limit=max(0, int(args.limit)),
        dry_run=bool(args.dry_run),
    )

    logger.info("Backfill done | processed=%d projected=%d skipped=%d", processed, projected, skipped)
    return 0


def main() -> int:
    load_dotenv(PROJECT_ROOT / ".env")
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    parser = _build_parser()
    args = parser.parse_args()

    try:
        return asyncio.run(_main_async(args))
    except FileNotFoundError as exc:
        logger.error(str(exc))
        return 2
    except KeyboardInterrupt:
        logger.warning("Interrupted")
        return 130


if __name__ == "__main__":
    raise SystemExit(main())
