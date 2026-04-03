import hashlib
import logging
from datetime import datetime, timezone

from pipeline.core.schemas import IngestionLocation, UnifiedIngestionEvent
from .base import PeriodicIngestor

logger = logging.getLogger(__name__)

FALLBACK_INDIA_COORDS = (20.5937, 78.9629)
RELIEFWEB_API = "https://api.reliefweb.int/v2/disasters"

TYPE_MAP = {
    "flood": "flood",
    "storm": "cyclone",
    "cyclone": "cyclone",
    "earthquake": "earthquake",
    "epidemic": "medical",
    "disease": "medical",
    "fire": "fire",
    "drought": "food",
}


class ReliefWebIngestor(PeriodicIngestor):
    """Ingest India-relevant disaster notices from ReliefWeb API (public/free)."""

    def __init__(self, interval_seconds: int = 1800, app_name: str = "sevasetu"):
        super().__init__(name="ReliefWeb", interval_seconds=interval_seconds)
        self.app_name = app_name

    async def fetch_events(self) -> list[UnifiedIngestionEvent]:
        payload = await self.request_json(
            RELIEFWEB_API,
            params={
                "appname": self.app_name,
                "limit": 50,
                "sort[]": "date:desc",
                "profile": "full",
                "filter[field]": "country.iso3",
                "filter[value]": "IND",
            },
            timeout=20.0,
            retries=2,
        )

        data = payload.get("data", []) if isinstance(payload, dict) else []
        events: list[UnifiedIngestionEvent] = []

        for item in data:
            fields = item.get("fields", {}) if isinstance(item, dict) else {}
            title = str(fields.get("name") or "ReliefWeb disaster")
            description = str(fields.get("description") or title)
            text = f"{title} {description}".lower()
            need_type = self._classify_need_type(text)
            if not need_type:
                continue

            created = self._parse_iso_datetime(fields.get("date", {}).get("created"))
            if created is None:
                created = datetime.now(timezone.utc)

            raw_id = f"reliefweb:{item.get('id', title)}"
            event_id = hashlib.sha256(raw_id.encode()).hexdigest()[:24]

            events.append(
                UnifiedIngestionEvent(
                    id=f"RWB-{event_id}",
                    source="RELIEFWEB",
                    timestamp=created,
                    location=IngestionLocation(
                        latitude=FALLBACK_INDIA_COORDS[0],
                        longitude=FALLBACK_INDIA_COORDS[1],
                    ),
                    need_type=need_type,
                    severity=self._infer_severity(text),
                    confidence_score=0.80,
                    description=title,
                    metadata={
                        "source_name": "ReliefWeb",
                        "url": fields.get("url_alias") or "",
                        "countries": [
                            country.get("name")
                            for country in fields.get("country", [])
                            if isinstance(country, dict)
                        ],
                    },
                )
            )

        logger.info("[ReliefWeb] normalized %d events", len(events))
        return events

    def _classify_need_type(self, text: str) -> str | None:
        for token, mapped in TYPE_MAP.items():
            if token in text:
                return mapped
        return None

    def _infer_severity(self, text: str) -> str:
        if any(word in text for word in ["severe", "critical", "emergency", "deaths"]):
            return "high"
        if any(word in text for word in ["warning", "alert", "affected"]):
            return "moderate"
        return "green"

    def _parse_iso_datetime(self, value: str | None) -> datetime | None:
        if not value:
            return None
        try:
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
            return dt.astimezone(timezone.utc)
        except Exception:
            return None
