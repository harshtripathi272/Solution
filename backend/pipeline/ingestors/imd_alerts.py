import hashlib
import asyncio
import logging
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

import feedparser

from pipeline.core.schemas import IngestionLocation, UnifiedIngestionEvent
from .base import PeriodicIngestor

logger = logging.getLogger(__name__)

FALLBACK_INDIA_COORDS = (20.5937, 78.9629)

ALERT_KEYWORDS = {
    "cyclone": "cyclone",
    "storm": "cyclone",
    "flood": "flood",
    "heavy rain": "flood",
    "rainfall": "flood",
    "heat wave": "medical",
    "cold wave": "medical",
    "landslide": "other",
    "thunderstorm": "other",
}


class IMDAlertsIngestor(PeriodicIngestor):
    """Ingest public IMD warning feeds where available."""

    def __init__(self, feed_url: str, interval_seconds: int = 1200):
        super().__init__(name="IMD-ALERTS", interval_seconds=interval_seconds)
        self.feed_url = feed_url.strip()

    async def fetch_events(self) -> list[UnifiedIngestionEvent]:
        if not self.feed_url:
            logger.warning("[IMD-ALERTS] feed URL missing. Skipping worker iteration.")
            return []

        parsed = await asyncio.to_thread(feedparser.parse, self.feed_url)
        entries = getattr(parsed, "entries", [])
        events: list[UnifiedIngestionEvent] = []

        for item in entries[:50]:
            title = str(getattr(item, "title", ""))
            summary = str(getattr(item, "summary", ""))
            text = f"{title} {summary}".lower()

            need_type = self._classify_need_type(text)
            if not need_type:
                continue

            published = str(getattr(item, "published", ""))
            timestamp = self._parse_timestamp(published)
            raw_id = f"imd:{getattr(item, 'id', title)}:{timestamp.isoformat()}"
            event_id = hashlib.sha256(raw_id.encode()).hexdigest()[:24]

            events.append(
                UnifiedIngestionEvent(
                    id=f"IMD-{event_id}",
                    source="IMD_ALERTS",
                    timestamp=timestamp,
                    location=IngestionLocation(
                        latitude=FALLBACK_INDIA_COORDS[0],
                        longitude=FALLBACK_INDIA_COORDS[1],
                    ),
                    need_type=need_type,
                    severity=self._infer_severity(text),
                    confidence_score=0.84,
                    description=title or "IMD alert",
                    metadata={
                        "summary": summary,
                        "link": getattr(item, "link", ""),
                        "publisher": "IMD",
                    },
                )
            )

        logger.info("[IMD-ALERTS] normalized %d events", len(events))
        return events

    def _classify_need_type(self, text: str) -> str | None:
        for keyword, need_type in ALERT_KEYWORDS.items():
            if keyword in text:
                return need_type
        return None

    def _infer_severity(self, text: str) -> str:
        if any(token in text for token in ["red alert", "extremely heavy", "severe"]):
            return "high"
        if any(token in text for token in ["orange alert", "warning", "heavy"]):
            return "moderate"
        return "green"

    def _parse_timestamp(self, value: str) -> datetime:
        if value:
            try:
                dt = parsedate_to_datetime(value)
                if dt.tzinfo is None:
                    dt = dt.replace(tzinfo=timezone.utc)
                return dt.astimezone(timezone.utc)
            except Exception:
                pass
        return datetime.now(timezone.utc)
