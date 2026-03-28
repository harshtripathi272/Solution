import hashlib
import logging
from datetime import datetime, timezone

from pipeline.schemas import IngestionLocation, UnifiedIngestionEvent
from .base import PeriodicIngestor

logger = logging.getLogger(__name__)


DEFAULT_IN_CITIES = [
    ("Delhi", 28.6139, 77.2090),
    ("Mumbai", 19.0760, 72.8777),
    ("Kolkata", 22.5726, 88.3639),
    ("Chennai", 13.0827, 80.2707),
]


class OpenWeatherIngestor(PeriodicIngestor):
    API_URL = "https://api.openweathermap.org/data/3.0/onecall"

    def __init__(self, api_key: str, interval_seconds: int = 420):
        super().__init__(name="OpenWeather", interval_seconds=interval_seconds)
        self.api_key = api_key

    async def fetch_events(self) -> list[UnifiedIngestionEvent]:
        if not self.api_key:
            logger.warning("[OpenWeather] API key missing. Skipping worker iteration.")
            return []

        events: list[UnifiedIngestionEvent] = []
        for city, lat, lon in DEFAULT_IN_CITIES:
            data = await self.request_json(
                self.API_URL,
                params={
                    "lat": lat,
                    "lon": lon,
                    "appid": self.api_key,
                    "exclude": "minutely,hourly,daily,current",
                },
            )

            for alert in data.get("alerts", []):
                start = alert.get("start")
                timestamp = datetime.fromtimestamp(start, tz=timezone.utc) if start else self.now_utc()
                title = str(alert.get("event", "weather alert"))
                lower = title.lower()

                need_type = "flood" if any(k in lower for k in ["flood", "rain", "storm", "cyclone"]) else "other"
                severity = "high" if "extreme" in lower or "cyclone" in lower else "moderate"

                raw_id = f"owm:{city}:{title}:{int(timestamp.timestamp())}"
                event_id = hashlib.sha256(raw_id.encode()).hexdigest()[:24]

                events.append(
                    UnifiedIngestionEvent(
                        id=f"OWM-{event_id}",
                        source="OPENWEATHERMAP",
                        timestamp=timestamp,
                        location=IngestionLocation(latitude=lat, longitude=lon),
                        need_type=need_type,
                        severity=severity,
                        confidence_score=0.8,
                        description=title,
                        metadata={
                            "sender": alert.get("sender_name"),
                            "description": alert.get("description", ""),
                            "region": city,
                        },
                    )
                )

        logger.info("[OpenWeather] normalized %d events", len(events))
        return events
