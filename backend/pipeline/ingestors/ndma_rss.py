import hashlib
import logging
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime

import feedparser

from pipeline.core.schemas import IngestionLocation, UnifiedIngestionEvent
from .base import PeriodicIngestor

logger = logging.getLogger(__name__)


CRISIS_KEYWORDS = {
    "flood": "flood",
    "earthquake": "earthquake",
    "cyclone": "cyclone",
    "storm": "cyclone",
    "landslide": "other",
    "fire": "fire",
    "health": "medical",
}


class NDMARSSIngestor(PeriodicIngestor):
    def __init__(self, feed_url: str, interval_seconds: int = 300):
        super().__init__(name="NDMA-RSS", interval_seconds=interval_seconds)
        self.feed_url = feed_url

    async def fetch_events(self) -> list[UnifiedIngestionEvent]:
        parsed = feedparser.parse(self.feed_url)
        entries = getattr(parsed, "entries", [])
        events: list[UnifiedIngestionEvent] = []

        for item in entries[:30]:
            title = str(getattr(item, "title", ""))
            summary = str(getattr(item, "summary", ""))
            text = f"{title} {summary}".lower()
            need_type = self._classify_need_type(text)
            if not need_type:
                continue

            lat, lon = self._extract_lat_lon(item)
            if lat is None or lon is None:
                continue

            published = getattr(item, "published", "")
            timestamp = self._parse_timestamp(published)
            raw_id = f"ndma:{getattr(item, 'id', title)}:{lat:.3f}:{lon:.3f}"
            event_id = hashlib.sha256(raw_id.encode()).hexdigest()[:24]

            events.append(
                UnifiedIngestionEvent(
                    id=f"NDMA-{event_id}",
                    source="NDMA_SACHET",
                    timestamp=timestamp,
                    location=IngestionLocation(latitude=lat, longitude=lon),
                    need_type=need_type,
                    severity="high",
                    confidence_score=0.85,
                    description=title or "NDMA alert",
                    metadata={
                        "summary": summary,
                        "link": getattr(item, "link", ""),
                        "region": getattr(item, "author", "india"),
                    },
                )
            )

        logger.info("[NDMA-RSS] normalized %d events", len(events))
        return events

    def _classify_need_type(self, text: str) -> str | None:
        for keyword, need in CRISIS_KEYWORDS.items():
            if keyword in text:
                return need
        return None

    def _extract_lat_lon(self, item) -> tuple[float | None, float | None]:
        geo_lat = getattr(item, "geo_lat", None)
        geo_long = getattr(item, "geo_long", None)
        if geo_lat and geo_long:
            return float(geo_lat), float(geo_long)

        # Many feeds expose georss_point as "lat lon".
        georss_point = getattr(item, "georss_point", None)
        if georss_point and isinstance(georss_point, str) and " " in georss_point:
            parts = georss_point.split()
            try:
                return float(parts[0]), float(parts[1])
            except Exception:
                return None, None
        return None, None

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
