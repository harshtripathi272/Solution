"""
Unified extraction engine for both text (NER) and PDF documents.

Temporary provider switch:
- Uses OpenAI SDK against NVIDIA endpoint.
- Preserves existing extractor interface to avoid pipeline changes.
"""

from __future__ import annotations

import asyncio
import ast
import hashlib
import io
import json
import logging
import os
import re
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

import httpx

logger = logging.getLogger(__name__)

try:
    from openai import OpenAI  # type: ignore
    _OPENAI_AVAILABLE = True
except ImportError:
    _OPENAI_AVAILABLE = False

try:
    from pypdf import PdfReader  # type: ignore
    _PDF_READER_AVAILABLE = True
except ImportError:
    _PDF_READER_AVAILABLE = False


class ExtractionError(Exception):
    """Base exception for extraction failures."""


class DocumentDownloadError(ExtractionError):
    """Raised when PDF download fails."""

    def __init__(self, message: str, status_code: int | None = None):
        super().__init__(message)
        self.status_code = status_code


@dataclass
class UnifiedExtractionResult:
    places: list[str] = field(default_factory=list)
    need_type: str = "other"
    severity: str = "moderate"
    confidence: float = 0.5
    population_affected: int = 0
    seasonal_urgency: str = ""
    vulnerable_groups: list[str] = field(default_factory=list)
    interventions: list[str] = field(default_factory=list)
    infrastructure_gaps: list[dict[str, Any]] = field(default_factory=list)
    source_excerpt: str = ""
    raw_json: dict[str, Any] = field(default_factory=dict)
    document_sha256: str = ""
    publication_date: Optional[datetime] = None


class GeminiExtractor:
    """
    Backward-compatible class name.

    Internally uses OpenAI SDK with NVIDIA endpoint:
    - base_url: https://integrate.api.nvidia.com/v1
    - model: stepfun-ai/step-3.5-flash
    - key env: NVIDIA_API_KEY
    """

    _MODEL_NAME = "moonshotai/kimi-k2-thinking"
    _MAX_TEXT_LEN = 1500
    _MAX_PDF_MB = 20
    _MAX_PDF_TEXT_LEN = 12000

    def __init__(self) -> None:
        self._enabled = False
        self._client: OpenAI | None = None
        self._model_name = os.getenv("DOC_STREAM_LLM_MODEL", self._MODEL_NAME).strip() or self._MODEL_NAME
        self._max_pdf_mb = int(os.getenv("DOC_STREAM_MAX_PDF_MB", str(self._MAX_PDF_MB)))
        self._request_timeout_s = float(os.getenv("DOC_STREAM_LLM_TIMEOUT_SECONDS", "90"))
        self._connect_timeout_s = float(os.getenv("DOC_STREAM_LLM_CONNECT_TIMEOUT_SECONDS", "10"))
        self._max_retries = int(os.getenv("DOC_STREAM_LLM_MAX_RETRIES", "1"))
        self._thinking_enabled = os.getenv("DOC_STREAM_LLM_THINKING", "false").strip().lower() == "true"
        self._max_tokens_text = int(os.getenv("DOC_STREAM_LLM_MAX_TOKENS_TEXT", "1024"))
        self._max_tokens_pdf = int(os.getenv("DOC_STREAM_LLM_MAX_TOKENS_PDF", "2048"))
        self._semaphore = asyncio.Semaphore(3) # Limit concurrent AI calls to prevent 504s
        self._init_client()

    def _init_client(self) -> None:
        api_key = os.getenv("NVIDIA_API_KEY", "").strip()
        if not api_key:
            logger.info("[UnifiedExtractor] NVIDIA_API_KEY not set — extraction disabled.")
            return
        if not _OPENAI_AVAILABLE:
            logger.warning("[UnifiedExtractor] openai package not installed — extraction disabled.")
            return
        try:
            self._client = OpenAI(
                base_url="https://integrate.api.nvidia.com/v1",
                api_key=api_key,
                timeout=httpx.Timeout(self._request_timeout_s, connect=self._connect_timeout_s),
                max_retries=self._max_retries,
            )
            self._enabled = True
            logger.info(
                "[UnifiedExtractor] NVIDIA extractor ready (timeout=%ss, connect=%ss, retries=%s, thinking=%s ,model=%s).",
                self._request_timeout_s,
                self._connect_timeout_s,
                self._max_retries,
                self._thinking_enabled,
                self._model_name
            )
            logger.info("[UnifiedExtractor] Using model: %s", self._model_name)
        except Exception as exc:
            logger.error("[UnifiedExtractor] Failed to initialize OpenAI client: %s", exc)

    async def extract(self, text: str) -> Optional[UnifiedExtractionResult]:
        if not self._enabled or not text:
            return None

        prompt = self._build_text_prompt(text[: self._MAX_TEXT_LEN])
        payload = await self._chat_completion_json(prompt, max_tokens=self._max_tokens_text)
        if payload is None:
            return None
        return self._result_from_payload(payload)

    async def extract_from_pdf_bytes(
        self,
        pdf_bytes: bytes,
        source_org: str,
        pdf_url: str = "",
        text_hint: str = "",
        publication_date_hint: str | None = None,
    ) -> Optional[UnifiedExtractionResult]:
        if not self._enabled:
            return None

        parsed_publication_date = self._parse_publication_date(publication_date_hint)
        sha256_hex = hashlib.sha256(pdf_bytes).hexdigest()

        extracted_text = self._extract_text_from_pdf(pdf_bytes)
        if not extracted_text and not text_hint:
            logger.warning("[UnifiedExtractor] No PDF text extracted and no text_hint available for %s", pdf_url)
            return None

        prompt = self._build_pdf_prompt(
            source_org=source_org,
            pdf_url=pdf_url,
            text_hint=text_hint,
            extracted_pdf_text=extracted_text,
        )
        payload = await self._chat_completion_json(prompt, max_tokens=self._max_tokens_pdf)
        if payload is None:
            return None

        return self._result_from_payload(
            payload,
            document_sha256=sha256_hex,
            publication_date=parsed_publication_date,
            source_excerpt_fallback=text_hint,
        )

    async def extract_from_pdf_url(
        self,
        pdf_url: str,
        source_org: str,
        publication_date_hint: str | None = None,
        text_hint: str | None = None,
    ) -> Optional[UnifiedExtractionResult]:
        if not self._enabled:
            return None

        buffer, sha256_hex = await self._download_pdf_to_memory(pdf_url)
        parsed_publication_date = self._parse_publication_date(publication_date_hint)
        extracted_text = self._extract_text_from_pdf(buffer.getvalue())
        hint = text_hint or ""

        if not extracted_text and not hint:
            logger.warning("[UnifiedExtractor] No PDF text extracted and no text_hint available for %s", pdf_url)
            return None

        prompt = self._build_pdf_prompt(
            source_org=source_org,
            pdf_url=pdf_url,
            text_hint=hint,
            extracted_pdf_text=extracted_text,
        )
        payload = await self._chat_completion_json(prompt, max_tokens=self._max_tokens_pdf)
        if payload is None:
            return None

        return self._result_from_payload(
            payload,
            document_sha256=sha256_hex,
            publication_date=parsed_publication_date,
            source_excerpt_fallback=hint,
        )

    async def generate_simple_text(self, prompt: str, system_instruction: str = "You are a helpful assistant.") -> str:
        """Generic text generation (non-JSON) for summaries/explanations."""
        if not self._client or not self._enabled:
            return ""

        async def _sync_call() -> Any:
            return self._client.chat.completions.create(
                model=self._model_name,
                messages=[
                    {"role": "system", "content": system_instruction},
                    {"role": "user", "content": prompt},
                ],
                temperature=0.7,  # Higher temperature for creative/prose generation
                max_tokens=self._max_tokens_text,
                stream=False,
                extra_body={"chat_template_kwargs": {"thinking": self._thinking_enabled}},
            )

        try:
            async with self._semaphore:
                logger.info("[UnifiedExtractor] Starting NVIDIA prose generation...")
                completion = await asyncio.to_thread(_sync_call)
                return self._extract_completion_text(completion).strip()
        except Exception as exc:
            logger.warning("[UnifiedExtractor] Prose generation failed: %s", exc)
            return ""

    async def _chat_completion_json(self, prompt: str, max_tokens: int) -> Optional[dict[str, Any]]:
        if not self._client:
            return None

        def _sync_call() -> Any:
            kwargs: dict[str, Any] = {
                "model": self._model_name,
                "messages": [
                    {
                        "role": "system",
                        "content": (
                            "You are a strict information extraction engine. "
                            "Return only one valid JSON object. "
                            "Do not include reasoning, analysis, markdown, or instruction text."
                        ),
                    },
                    {"role": "user", "content": prompt},
                ],
                "temperature": 0.2,
                "top_p": 0.95,
                "max_tokens": max_tokens,
                "stream": False,
                "response_format": {"type": "json_object"},
            }
            # Explicitly set thinking in all cases; reasoning models may default to enabled.
            kwargs["extra_body"] = {"chat_template_kwargs": {"thinking": self._thinking_enabled}}
            try:
                return self._client.chat.completions.create(**kwargs)
            except Exception as exc:
                # Some providers/models may not support response_format.
                if "response_format" not in str(exc).lower():
                    raise
                kwargs.pop("response_format", None)
                return self._client.chat.completions.create(**kwargs)

        try:
            async with self._semaphore:
                start = time.perf_counter()
                logger.info("[UnifiedExtractor] Starting NVIDIA extraction call...")
                completion = await asyncio.to_thread(_sync_call)
                elapsed = time.perf_counter() - start
                logger.info("[UnifiedExtractor] NVIDIA extraction completed in %.2fs", elapsed)
                content = self._extract_completion_text(completion)
                return self._parse_json_payload(content)
        except Exception as exc:
            logger.warning("[UnifiedExtractor] LLM extraction call failed (504/RateLimit?): %s", exc)
            return None

    @staticmethod
    def _extract_completion_text(completion: Any) -> str:
        choices = getattr(completion, "choices", None) or []
        if not choices:
            return ""
        message = getattr(choices[0], "message", None)
        if message is None:
            return ""

        content = getattr(message, "content", "")
        if isinstance(content, str) and content.strip():
            return content

        if isinstance(content, list):
            parts: list[str] = []
            for item in content:
                if isinstance(item, dict) and isinstance(item.get("text"), str):
                    parts.append(item["text"])
                    continue
                text_attr = getattr(item, "text", None)
                if isinstance(text_attr, str):
                    parts.append(text_attr)
            if parts:
                return "\n".join(parts)

        # Only use reasoning_content if content is completely empty
        reasoning = getattr(message, "reasoning_content", None)
        if isinstance(reasoning, str) and reasoning.strip():
            logger.debug("[UnifiedExtractor] Falling back to reasoning_content")
            return reasoning

        return str(content or "")

    @staticmethod
    def _parse_json_payload(raw: str) -> Optional[dict[str, Any]]:
        cleaned = re.sub(r"```(?:json)?", "", raw or "").strip("` \n")
        if not cleaned:
            return None

        # Strip chain-of-thought blocks emitted by some reasoning models.
        cleaned = re.sub(r"<think>[\s\S]*?</think>", "", cleaned, flags=re.IGNORECASE).strip()
        if "</think>" in cleaned:
            cleaned = cleaned.split("</think>")[-1].strip()

        # Some models prepend labels like "JSON:" before the object.
        cleaned = re.sub(r"^\s*json\s*:\s*", "", cleaned, flags=re.IGNORECASE)

        # If prose remains, trim everything before the first opening brace.
        first_brace = cleaned.find("{")
        if first_brace > 0:
            cleaned = cleaned[first_brace:]

        try:
            data = json.loads(cleaned)
            return data if isinstance(data, dict) else None
        except json.JSONDecodeError:
            # Extract top-level {...} candidates and prefer the last one.
            candidates: list[str] = []
            depth = 0
            start = -1
            for i, ch in enumerate(cleaned):
                if ch == "{":
                    if depth == 0:
                        start = i
                    depth += 1
                elif ch == "}":
                    if depth > 0:
                        depth -= 1
                        if depth == 0 and start >= 0:
                            candidates.append(cleaned[start:i + 1])

            for candidate in reversed(candidates):
                try:
                    data = json.loads(candidate)
                    if isinstance(data, dict):
                        return data
                except json.JSONDecodeError:
                    try:
                        obj = ast.literal_eval(candidate)
                        if isinstance(obj, dict):
                            return obj
                    except Exception:
                        continue

            logger.warning("[UnifiedExtractor] JSON parse failed after cleanup. Raw head (500 chars): %s", cleaned[:500])
            return None

    def _build_text_prompt(self, text: str) -> str:
        return f"""\
Extract structured humanitarian crisis data from the India-focused text below.
Output exactly one valid JSON object only.

Required JSON schema:
{{
    "places": ["most_specific_place", "district", "state"],
    "need_types": ["one or more of medical|water_sanitation|food|shelter|education|protection|livelihood|other"],
    "severity": "critical|high|moderate|low",
    "confidence": 0.0,
    "infrastructure_damage_score": 0.0,
    "road_accessibility_risk": 0.0,
    "water_access_severity": 3,
    "health_service_severity": 3
}}

Rules:
- Use real Indian place names only.
- If uncertain, keep conservative confidence.
- Identify ALL relevant need_types (e.g. if both food and water are mentioned, include both).
- `confidence` must be a number between 0 and 1.
- Do not repeat schema, rules, or the input text.
- No markdown, no explanation, no XML tags, JSON only.

Text:
{text}
"""

    def _build_pdf_prompt(self, source_org: str, pdf_url: str, text_hint: str, extracted_pdf_text: str) -> str:
        return f"""\
You are extracting structured humanitarian intelligence from NGO reports in India.
Identify ALL relevant needs mentioned.
Return ONLY valid JSON and follow this schema exactly:
{{
  "places": ["village/block/district/state mentions"],
  "need_types": ["one or more of medical|water_sanitation|food|shelter|education|protection|livelihood|other"],
  "severity_score": 1,
  "severity": "critical|high|moderate|low",
  "confidence": 0.0,
  "population_affected": 0,
  "recommended_interventions": ["actionable intervention"],
  "seasonal_urgency": "pre-monsoon|monsoon|post-monsoon|harvest|summer|winter|none",
  "vulnerable_groups": ["women|children|elderly|disabled|tribal|other"],
  "infrastructure_damage_score": 0.0,
  "road_accessibility_risk": 0.3,
  "security_constraint_risk": 0.2,
  "water_access_severity": 3,
  "food_security_severity": 3,
  "health_service_severity": 3,
  "infrastructure_gaps": [
    {{"type": "water|health|roads|shelter|sanitation|education|other", "status": "damaged|missing|insufficient|functional", "count": 0}}
  ],
  "source_excerpt": "max 500 chars"
}}

Context:
- Source NGO: {source_org}
- PDF URL: {pdf_url}
- Web snippet hint: {text_hint[:700]}

PDF extracted text (truncated):
{extracted_pdf_text[: self._MAX_PDF_TEXT_LEN]}
""".strip()

    @staticmethod
    def _extract_text_from_pdf(pdf_bytes: bytes) -> str:
        if not _PDF_READER_AVAILABLE:
            logger.warning("[UnifiedExtractor] pypdf not installed; PDF text extraction unavailable.")
            return ""
        try:
            reader = PdfReader(io.BytesIO(pdf_bytes))
            parts: list[str] = []
            # Limit to first 10 pages to prevent LLM context overflow and speed up throughput
            max_pages = 10
            for i, page in enumerate(reader.pages):
                if i >= max_pages:
                    logger.debug("[UnifiedExtractor] Truncating PDF text at %d pages", max_pages)
                    break
                text = page.extract_text() or ""
                if text.strip():
                    parts.append(text)
            return "\n".join(parts)
        except Exception as exc:
            logger.warning("[UnifiedExtractor] Failed to parse PDF text: %s", exc)
            return ""

    async def _download_pdf_to_memory(self, pdf_url: str) -> tuple[io.BytesIO, str]:
        max_bytes = self._max_pdf_mb * 1024 * 1024
        hasher = hashlib.sha256()
        chunks: list[bytes] = []
        total = 0

        async with httpx.AsyncClient(timeout=60.0, follow_redirects=True) as client:
            try:
                async with client.stream("GET", pdf_url) as response:
                    response.raise_for_status()
                    ctype = (response.headers.get("content-type") or "").lower()
                    if "pdf" not in ctype and not pdf_url.lower().endswith(".pdf"):
                        logger.warning("[UnifiedExtractor] URL does not look like PDF: %s (%s)", pdf_url, ctype)

                    async for chunk in response.aiter_bytes():
                        if not chunk:
                            continue
                        total += len(chunk)
                        if total > max_bytes:
                            raise DocumentDownloadError(
                                f"PDF exceeds max prototype size ({self._max_pdf_mb}MB)",
                                status_code=response.status_code,
                            )
                        hasher.update(chunk)
                        chunks.append(chunk)
            except httpx.HTTPStatusError as exc:
                status = exc.response.status_code if exc.response is not None else None
                raise DocumentDownloadError(f"PDF download failed for {pdf_url}", status_code=status) from exc
            except httpx.HTTPError as exc:
                raise DocumentDownloadError(f"PDF download error for {pdf_url}: {exc}") from exc

        return io.BytesIO(b"".join(chunks)), hasher.hexdigest()

    def _result_from_payload(
        self,
        payload: dict[str, Any],
        document_sha256: str = "",
        publication_date: Optional[datetime] = None,
        source_excerpt_fallback: str = "",
    ) -> UnifiedExtractionResult:
        places = self._normalize_list(payload.get("places")) or self._normalize_list(payload.get("locations"))
        
        # Handle multiple need_types
        raw_needs = payload.get("need_types") or payload.get("need_type") or "other"
        if isinstance(raw_needs, list):
            need_type = ", ".join(self._normalize_need_type(str(n)) for n in raw_needs if n)
        else:
            need_type = self._normalize_need_type(str(raw_needs))
            
        severity = self._normalize_severity(
            raw_label=str(payload.get("severity", "")),
            raw_score=payload.get("severity_score"),
        )
        confidence = max(0.0, min(self._safe_float(payload.get("confidence"), default=0.55), 1.0))

        vulnerable_groups = self._normalize_list(payload.get("vulnerable_groups"))
        interventions = self._normalize_list(payload.get("recommended_interventions"))
        infra = payload.get("infrastructure_gaps") or []
        if not isinstance(infra, list):
            infra = []

        population_affected = self._safe_int(
            payload.get("population_affected") or payload.get("beneficiary_count"),
            default=0,
        )

        excerpt = payload.get("source_excerpt") or payload.get("summary") or source_excerpt_fallback
        excerpt = " ".join(str(excerpt).split())[:700]

        return UnifiedExtractionResult(
            places=[str(p).strip() for p in places if str(p).strip()],
            need_type=need_type,
            severity=severity,
            confidence=confidence,
            population_affected=max(0, population_affected),
            seasonal_urgency=str(payload.get("seasonal_urgency", "")).strip(),
            vulnerable_groups=[str(v).strip() for v in vulnerable_groups if str(v).strip()],
            interventions=[str(i).strip() for i in interventions if str(i).strip()],
            infrastructure_gaps=infra,
            source_excerpt=excerpt,
            raw_json=payload,
            document_sha256=document_sha256,
            publication_date=publication_date,
        )

    @staticmethod
    def _normalize_need_type(value: str) -> str:
        low = (value or "").strip().lower()
        allowed = {
            "medical",
            "water_sanitation",
            "food",
            "shelter",
            "education",
            "protection",
            "livelihood",
            "other",
        }
        if low in allowed:
            return low
        if any(x in low for x in ["water", "sanitation", "wash"]):
            return "water_sanitation"
        if any(x in low for x in ["health", "medicine", "medical"]):
            return "medical"
        if any(x in low for x in ["agri", "income", "work", "livelihood"]):
            return "livelihood"
        if "education" in low or "school" in low:
            return "education"
        if "protect" in low or "violence" in low or "safety" in low:
            return "protection"
        if "food" in low or "hunger" in low or "nutrition" in low:
            return "food"
        if any(x in low for x in ["shelter", "housing", "camp", "refugee"]):
            return "shelter"
        return "other"

    @staticmethod
    def _normalize_severity(raw_label: str, raw_score: Any) -> str:
        score = GeminiExtractor._safe_int(raw_score, default=-1)
        if score >= 8:
            return "critical"
        if score >= 6:
            return "high"
        if score >= 3:
            return "moderate"
        if score >= 0:
            return "low"

        label = str(raw_label or "").strip().lower()
        if label in {"critical", "high", "moderate", "low"}:
            return label
        return "moderate"

    @staticmethod
    def _normalize_list(value: Any) -> list[str]:
        if isinstance(value, str):
            return [value]
        if isinstance(value, list):
            return [str(v).strip() for v in value if v]
        return []

    @staticmethod
    def _safe_int(value: Any, default: int = 0) -> int:
        try:
            return int(float(value))
        except Exception:
            return default

    @staticmethod
    def _safe_float(value: Any, default: float = 0.0) -> float:
        try:
            return float(value)
        except Exception:
            return default

    @staticmethod
    def _parse_publication_date(raw: Optional[str]) -> Optional[datetime]:
        if not raw:
            return None
        value = raw.strip()
        if not value:
            return None

        for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%d-%m-%Y", "%b %d, %Y", "%B %d, %Y"):
            try:
                return datetime.strptime(value, fmt).replace(tzinfo=timezone.utc)
            except ValueError:
                continue

        try:
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc)
        except ValueError:
            return None


# Global singletons
gemini_extractor = GeminiExtractor()
nvidia_extractor = gemini_extractor  # Alias for newer code

