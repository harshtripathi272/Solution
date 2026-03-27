import httpx
import logging
from datetime import datetime, timezone
import uuid

from pipeline.schemas import IngestionLocation, UnifiedIngestionEvent
from .base import PeriodicIngestor

logger = logging.getLogger(__name__)

class GDACSIngestor(PeriodicIngestor):
    """
    Tier 1 Official Alert Source. 
    Pulls Global Disaster Alert and Coordination System (GDACS) API automatically.
    """
    API_URL = "https://www.gdacs.org/gdacsapi/api/Events/geteventlist/EVENTS4APP"

    def __init__(self, interval_seconds: int = 600):
        super().__init__(name="GDACS", interval_seconds=interval_seconds)

    async def fetch_events(self) -> list[UnifiedIngestionEvent]:
        logger.info("[GDACS] Fetching latest official alerts from GDACS...")
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(self.API_URL, timeout=10.0)
                response.raise_for_status()
                data = response.json()
        except Exception as e:
            logger.error(f"[GDACS] Failed to fetch data: {str(e)}")
            return []

        features = data.get("features", [])
        events: list[UnifiedIngestionEvent] = []
        
        for feature in features:
            props = feature.get("properties", {})
            geom = feature.get("geometry", {})
            
            # Map GDACS event type codes to ours
            event_type = str(props.get("eventtype", "")).lower()
            need_type = "other"
            if "fl" in event_type: need_type = "flood"
            elif "tc" in event_type: need_type = "cyclone"
            elif "eq" in event_type: need_type = "earthquake"
            elif "wf" in event_type: need_type = "fire"
            
            # Map Severity
            alert_level = str(props.get("alertlevel", "")).lower()
            severity = "unknown"
            if alert_level == "red": severity = "critical"
            elif alert_level == "orange": severity = "high"
            elif alert_level == "green": severity = "moderate"

            country = str(props.get("country", ""))
            
            coords = geom.get("coordinates", [0, 0])
            lon, lat = coords[0], coords[1]
            if lat == 0 and lon == 0:
                continue
            
            timestamp = datetime.now(timezone.utc)
            event = UnifiedIngestionEvent(
                id=f"GDACS-{props.get('eventid', uuid.uuid4())}",
                source="GDACS",
                timestamp=timestamp,
                location=IngestionLocation(latitude=lat, longitude=lon),
                need_type=need_type,
                severity=severity,
                description=props.get("htmldescription", "GDACS Official Alert"),
                confidence_score=0.95,
                metadata={"region": country, "radius_km": 100.0, **props},
            )
            events.append(event)
            
        logger.info("[GDACS] Successfully normalized %d official alerts.", len(events))
        return events

gdacs_ingestor = GDACSIngestor()
