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

CRISIS_KEYWORDS = {
    "flood": "flood",
    "cyclone": "cyclone",
    "storm": "cyclone",
    "rain": "flood",
    "landslide": "other",
    "earthquake": "earthquake",
    "health": "medical",
    "epidemic": "medical",
    "outbreak": "medical",
    "food": "food",
    "ration": "food",
    "water": "water_sanitation",
    "sanitation": "water_sanitation",
    "displacement": "displacement",
    "relief": "other",
}


class PIBRSSIngestor(PeriodicIngestor):
    """Ingest state-relevant public bulletins from PIB RSS feeds."""

    def __init__(self, feed_urls: list[str], interval_seconds: int = 1800):
        super().__init__(name="PIB-RSS", interval_seconds=interval_seconds)
        self.feed_urls = [url.strip() for url in feed_urls if url.strip()]

    async def fetch_events(self) -> list[UnifiedIngestionEvent]:
        if not self.feed_urls:
            logger.warning("[PIB-RSS] No feed URLs configured. Skipping worker iteration.")
            return []

        events: list[UnifiedIngestionEvent] = []
        for feed_url in self.feed_urls:
            parsed = await asyncio.to_thread(feedparser.parse, feed_url)
            entries = getattr(parsed, "entries", [])

            for item in entries[:40]:
                title = str(getattr(item, "title", ""))
                summary = str(getattr(item, "summary", ""))
                text = f"{title} {summary}".lower()
                need_type = self._classify_need_type(text)
                if not need_type:
                    continue

                published = str(getattr(item, "published", ""))
                timestamp = self._parse_timestamp(published)

                lat, lon = FALLBACK_INDIA_COORDS
                raw_id = f"pib:{feed_url}:{getattr(item, 'id', title)}"
                event_id = hashlib.sha256(raw_id.encode()).hexdigest()[:24]

                events.append(
                    UnifiedIngestionEvent(
                        id=f"PIB-{event_id}",
                        source="PIB_RSS",
                        timestamp=timestamp,
                        location=IngestionLocation(latitude=lat, longitude=lon),
                        need_type=need_type,
                        severity=self._infer_severity(text),
                        confidence_score=0.82,
                        description=title or "PIB bulletin",
                        metadata={
                            "summary": summary,
                            "link": getattr(item, "link", ""),
                            "publisher": "PIB",
                            "feed_url": feed_url,
                        },
                    )
                )

        logger.info("[PIB-RSS] normalized %d events", len(events))
        return events

    def _classify_need_type(self, text: str) -> str | None:
        for keyword, need in CRISIS_KEYWORDS.items():
            if keyword in text:
                return need
        return None

    def _infer_severity(self, text: str) -> str:
        if any(word in text for word in ["emergency", "severe", "critical", "deaths"]):
            return "high"
        if any(word in text for word in ["alert", "warning", "affected"]):
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
