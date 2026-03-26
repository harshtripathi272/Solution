import httpx
import logging
from datetime import datetime, timezone
import uuid

from pipeline.schemas import CrisisEvent, CrisisType, SeverityLevel, LocationMetadata, SkillMatrix
from pipeline.pubsub_mock import broker

logger = logging.getLogger(__name__)

class GDACSIngestor:
    """
    Tier 1 Official Alert Source. 
    Pulls Global Disaster Alert and Coordination System (GDACS) API automatically.
    """
    API_URL = "https://www.gdacs.org/gdacsapi/api/Events/geteventlist/EVENTS4APP"

    async def fetch_and_publish(self):
        logger.info("[GDACS] Fetching latest official alerts from GDACS...")
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(self.API_URL, timeout=10.0)
                response.raise_for_status()
                data = response.json()
        except Exception as e:
            logger.error(f"[GDACS] Failed to fetch data: {str(e)}")
            return

        features = data.get("features", [])
        events_published = 0
        
        for feature in features:
            props = feature.get("properties", {})
            geom = feature.get("geometry", {})
            
            # Map GDACS event type codes to ours
            event_type = str(props.get("eventtype", "")).lower()
            crisis_type = CrisisType.OTHER
            if "fl" in event_type: crisis_type = CrisisType.FLOOD
            elif "tc" in event_type: crisis_type = CrisisType.CYCLONE
            elif "eq" in event_type: crisis_type = CrisisType.EARTHQUAKE
            elif "wf" in event_type: crisis_type = CrisisType.FIRE
            
            # Map Severity
            alert_level = str(props.get("alertlevel", "")).lower()
            severity = SeverityLevel.UNKNOWN
            if alert_level == "red": severity = SeverityLevel.CRITICAL
            elif alert_level == "orange": severity = SeverityLevel.HIGH
            elif alert_level == "green": severity = SeverityLevel.MODERATE

            country = str(props.get("country", ""))
            
            coords = geom.get("coordinates", [0, 0])
            lon, lat = coords[0], coords[1]
            
            # Create standardized Internal Crisis payload
            event = CrisisEvent(
                id=f"GDACS-{props.get('eventid', uuid.uuid4())}",
                source="GDACS",
                tier=1, # Official Tier
                timestamp=datetime.now(timezone.utc), 
                type=crisis_type,
                severity=severity,
                location=LocationMetadata(
                    latitude=lat,
                    longitude=lon,
                    geohash="GDACS",
                    region_name=country,
                    radius_km=100.0 # Official alerts cover wide areas
                ),
                description=props.get("htmldescription", "GDACS Official Alert"),
                is_verified=True, # Official Tier matches are intrinsically verified
                skills_required=SkillMatrix(
                    requires_medical=True if severity == SeverityLevel.CRITICAL else False,
                    requires_rescue=True if crisis_type in [CrisisType.FLOOD, CrisisType.EARTHQUAKE] else False,
                    min_volunteers_needed=10 if severity == SeverityLevel.CRITICAL else 2
                ),
                raw_data=props
            )
            
            # Publish to Pub/Sub structure
            await broker.publish("official-alerts", event)
            events_published += 1
            
        logger.info(f"[GDACS] Successfully ingested and published {events_published} confirmed official alerts.")

gdacs_ingestor = GDACSIngestor()
