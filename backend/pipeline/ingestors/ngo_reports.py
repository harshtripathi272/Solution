from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

from pipeline.core.schemas import IngestionLocation, UnifiedIngestionEvent
from .base import PeriodicIngestor

logger = logging.getLogger(__name__)

FALLBACK_INDIA_COORDS = (20.5937, 78.9629)


class NGOReportsIngestor(PeriodicIngestor):
    def __init__(self, interval_seconds: int = 21600, max_reports: int = 80):
        super().__init__(name="NGOReports", interval_seconds=interval_seconds)
        self.max_reports = max_reports

    async def fetch_events(self, max_reports: int | None = None) -> list[UnifiedIngestionEvent]:
        max_pages = max_reports or self.max_reports
        records = await self._run_scrapy(max_pages=max_pages)

        events: list[UnifiedIngestionEvent] = []
        for rec in records:
            event = self._to_event(rec)
            if event:
                events.append(event)

        logger.info("[NGOReports] normalized %d events", len(events))
        return events

    async def _run_scrapy(self, max_pages: int) -> list[dict]:
        backend_root = Path(__file__).resolve().parents[2]
        with tempfile.NamedTemporaryFile(suffix=".jsonl", delete=False) as tmp:
            output_path = Path(tmp.name)

        cmd = [
            sys.executable,
            "-m",
            "scrapers.ngo_reports.run_spiders",
            "--output",
            str(output_path),
            "--max-pages",
            str(max_pages),
        ]

        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                cwd=str(backend_root),
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            _, stderr = await proc.communicate()
            if proc.returncode != 0:
                logger.error("[NGOReports] Scrapy run failed: %s", stderr.decode("utf-8", errors="ignore"))
                return []

            records: list[dict] = []
            if output_path.exists():
                for line in output_path.read_text(encoding="utf-8").splitlines():
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        records.append(json.loads(line))
                    except json.JSONDecodeError:
                        continue
            return records
        finally:
            try:
                output_path.unlink(missing_ok=True)
            except Exception:
                pass

    def _to_event(self, rec: dict) -> UnifiedIngestionEvent | None:
        title = str(rec.get("title", "")).strip()
        source_url = str(rec.get("source_url", "")).strip()
        if not title and not source_url:
            return None

        source_org = str(rec.get("source_org", "NGO")).strip()
        raw_text = str(rec.get("raw_text", "")).strip()
        snippet = str(rec.get("snippet", "")).strip()
        description = title or snippet[:160] or "NGO report"

        timestamp = self._parse_timestamp(rec.get("published_on"))
        need_type = self._infer_need_type(f"{title} {snippet} {raw_text}")
        severity = self._infer_severity(f"{title} {snippet} {raw_text}")

        lat, lon = FALLBACK_INDIA_COORDS
        region_tags = rec.get("region_tags") or []
        if not isinstance(region_tags, list):
            region_tags = []

        fingerprint = f"{source_org}|{source_url}|{rec.get('pdf_url', '')}|{rec.get('published_on', '')}"
        event_id = hashlib.sha256(fingerprint.encode("utf-8")).hexdigest()[:24]

        return UnifiedIngestionEvent(
            id=f"NGO-{event_id}",
            source=f"NGO_{source_org.upper().replace(' ', '_')}",
            timestamp=timestamp,
            location=IngestionLocation(latitude=lat, longitude=lon),
            need_type=need_type,
            severity=severity,
            confidence_score=0.62,
            description=description,
            metadata={
                "source_org": source_org,
                "source_url": source_url,
                "pdf_url": rec.get("pdf_url", ""),
                "published_on": rec.get("published_on", ""),
                "region_tags": region_tags,
                "snippet": snippet[:400],
                "raw_text": raw_text[:2000],
                "ingest_channel": "scrapy_playwright",
                "region": region_tags[0] if region_tags else "india",
            },
        )

    def _parse_timestamp(self, raw: object) -> datetime:
        if raw is None:
            return self.now_utc()
        value = str(raw).strip()
        if not value:
            return self.now_utc()

        for fmt in (
            "%Y-%m-%d",
            "%d/%m/%Y",
            "%m/%d/%Y",
            "%d-%m-%Y",
            "%b %d, %Y",
            "%B %d, %Y",
        ):
            try:
                dt = datetime.strptime(value, fmt)
                return dt.replace(tzinfo=timezone.utc)
            except ValueError:
                continue

        try:
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
            if dt.tzinfo is None:
                dt = dt.replace(tzinfo=timezone.utc)
            return dt.astimezone(timezone.utc)
        except ValueError:
            return self.now_utc()

    @staticmethod
    def _infer_need_type(text: str) -> str:
        lowered = text.lower()
        if "flood" in lowered or "waterlogging" in lowered:
            return "flood"
        if "drought" in lowered or "water scarcity" in lowered:
            return "food"
        if "malnutrition" in lowered or "health" in lowered or "medical" in lowered:
            return "medical"
        if "cyclone" in lowered or "storm" in lowered:
            return "cyclone"
        if "fire" in lowered:
            return "fire"
        return "other"

    @staticmethod
    def _infer_severity(text: str) -> str:
        lowered = text.lower()
        if any(k in lowered for k in ["critical", "severe", "urgent", "emergency"]):
            return "high"
        if any(k in lowered for k in ["alert", "warning", "risk"]):
            return "moderate"
        return "low"
