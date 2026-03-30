from __future__ import annotations

import hashlib
import io
import json
import logging
import os
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Optional

import httpx

logger = logging.getLogger(__name__)

try:
    import google.generativeai as genai  # type: ignore
    _GENAI_AVAILABLE = True
except ImportError:
    _GENAI_AVAILABLE = False


class DocumentDownloadError(Exception):
    def __init__(self, message: str, status_code: int | None = None):
        super().__init__(message)
        self.status_code = status_code


@dataclass
class DocumentExtractionResult:
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


class GeminiDocumentExtractor:
    """Prototype document extractor using Gemini Flash with zero-disk PDF streaming."""

    _MODEL_NAME = "gemini-2.0-flash"

    def __init__(self) -> None:
        self._enabled = False
        self._model = None
        self._max_pdf_mb = int(os.getenv("DOC_STREAM_MAX_PDF_MB", "20"))
        self._init_client()

    def _init_client(self) -> None:
        api_key = os.getenv("GEMINI_API_KEY", "").strip()
        if not api_key:
            logger.info("[DocExtractor] GEMINI_API_KEY not set — document extraction disabled.")
            return
        if not _GENAI_AVAILABLE:
            logger.warning("[DocExtractor] google-generativeai not installed — extraction disabled.")
            return
        try:
            genai.configure(api_key=api_key)
            self._model = genai.GenerativeModel(self._MODEL_NAME)
            self._enabled = True
            logger.info("[DocExtractor] Gemini Flash document extractor ready.")
        except Exception as exc:
            logger.error("[DocExtractor] Failed to initialize Gemini client: %s", exc)

    async def extract_from_pdf_url(
        self,
        pdf_url: str,
        source_org: str,
        publication_date_hint: str | None = None,
        text_hint: str | None = None,
    ) -> Optional[DocumentExtractionResult]:
        if not self._enabled:
            return None

        buffer, sha256_hex = await self._download_pdf_to_memory(pdf_url)
        parsed_publication_date = self._parse_publication_date(publication_date_hint)

        payload = await self._extract_with_gemini(
            pdf_bytes=buffer.getvalue(),
            source_org=source_org,
            pdf_url=pdf_url,
            text_hint=text_hint or "",
        )
        if payload is None:
            return None

        places = payload.get("places") or payload.get("locations") or []
        if isinstance(places, str):
            places = [places]
        if not isinstance(places, list):
            places = []

        vulnerable_groups = payload.get("vulnerable_groups") or []
        if isinstance(vulnerable_groups, str):
            vulnerable_groups = [vulnerable_groups]
        if not isinstance(vulnerable_groups, list):
            vulnerable_groups = []

        interventions = payload.get("recommended_interventions") or []
        if isinstance(interventions, str):
            interventions = [interventions]
        if not isinstance(interventions, list):
            interventions = []

        infra = payload.get("infrastructure_gaps") or []
        if not isinstance(infra, list):
            infra = []

        severity = self._to_severity(payload.get("severity_score"), payload.get("severity"))
        confidence = self._safe_float(payload.get("confidence"), default=0.55)

        affected = payload.get("population_affected") or payload.get("beneficiary_count") or 0
        affected_num = self._safe_int(affected, default=0)

        excerpt = payload.get("source_excerpt") or payload.get("summary") or (text_hint or "")
        excerpt = " ".join(str(excerpt).split())[:700]

        return DocumentExtractionResult(
            places=[str(p).strip() for p in places if str(p).strip()],
            need_type=self._normalize_need_type(str(payload.get("need_type", "other"))),
            severity=severity,
            confidence=max(0.0, min(confidence, 1.0)),
            population_affected=max(0, affected_num),
            seasonal_urgency=str(payload.get("seasonal_urgency", "")).strip(),
            vulnerable_groups=[str(v).strip() for v in vulnerable_groups if str(v).strip()],
            interventions=[str(i).strip() for i in interventions if str(i).strip()],
            infrastructure_gaps=infra,
            source_excerpt=excerpt,
            raw_json=payload,
            document_sha256=sha256_hex,
            publication_date=parsed_publication_date,
        )

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
                        logger.warning("[DocExtractor] URL does not look like PDF: %s (%s)", pdf_url, ctype)

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

        buffer = io.BytesIO(b"".join(chunks))
        return buffer, hasher.hexdigest()

    async def _extract_with_gemini(self, pdf_bytes: bytes, source_org: str, pdf_url: str, text_hint: str) -> Optional[dict[str, Any]]:
        prompt = f"""
You are extracting structured humanitarian intelligence from NGO reports in India.
Return ONLY valid JSON. Do not include markdown fences.
Use this schema exactly:
{{
  "places": ["village/block/district/state mentions"],
  "need_type": "one of medical|water_sanitation|food|shelter|education|protection|livelihood|other",
  "severity_score": 1,
  "confidence": 0.0,
  "population_affected": 0,
  "recommended_interventions": ["actionable intervention"],
  "seasonal_urgency": "pre-monsoon|monsoon|post-monsoon|harvest|summer|winter|none",
  "vulnerable_groups": ["women|children|elderly|disabled|tribal|other"],
  "infrastructure_gaps": [
    {{"type": "water|health|roads|shelter|sanitation|education|other", "status": "damaged|missing|insufficient|functional", "count": 0}}
  ],
  "source_excerpt": "max 500 chars"
}}

Context:
- Source NGO: {source_org}
- PDF URL: {pdf_url}
- Optional page context from spider (may be noisy): {text_hint[:700]}
""".strip()

        generation_config = genai.GenerationConfig(
            temperature=0.1,
            response_mime_type="application/json",
        )

        try:
            response = await self._model.generate_content_async(
                [
                    {"mime_type": "application/pdf", "data": pdf_bytes},
                    prompt,
                ],
                generation_config=generation_config,
            )
            raw = (response.text or "").strip()
            if not raw:
                return None
            try:
                return json.loads(raw)
            except json.JSONDecodeError:
                cleaned = raw.strip("` \n")
                return json.loads(cleaned)
        except Exception as exc:
            logger.warning("[DocExtractor] Gemini extraction failed: %s", exc)
            return None

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
        if "water" in low or "sanitation" in low or "wash" in low:
            return "water_sanitation"
        if "health" in low or "medicine" in low:
            return "medical"
        if "agri" in low or "income" in low or "work" in low:
            return "livelihood"
        return "other"

    @staticmethod
    def _to_severity(score: Any, label: Any) -> str:
        value = GeminiDocumentExtractor._safe_int(score, default=-1)
        if value >= 8:
            return "critical"
        if value >= 6:
            return "high"
        if value >= 3:
            return "moderate"
        if value >= 0:
            return "low"

        low = str(label or "").strip().lower()
        if low in {"critical", "high", "moderate", "low"}:
            return low
        return "moderate"

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


document_extractor = GeminiDocumentExtractor()
