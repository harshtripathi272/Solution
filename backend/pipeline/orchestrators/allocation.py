import logging
from typing import List

from pipeline.core.pubsub import broker
from pipeline.core.schemas import CrisisEvent
from pipeline.storage.location import location_store

logger = logging.getLogger(__name__)

# Skill-tag requirements per crisis type
CRISIS_SKILL_MAP = {
    "flood":     ["rescue"],
    "earthquake":["rescue", "medical"],
    "cyclone":   ["rescue"],
    "medical":   ["medical"],
    "fire":      ["rescue"],
    "violence":  ["counseling"],
    "other":     [],
}

class AllocationEngine:
    def start(self):
        broker.subscribe("official-alerts", "volunteer-allocator", self._handle_crisis)
        broker.subscribe("verified-crisis",  "volunteer-allocator-v", self._handle_crisis)
        logger.info("Volunteer Allocation Engine (Redis GEO) running. Ready to dispatch.")

    async def _handle_crisis(self, event: CrisisEvent):
        severity_meta = {}
        if isinstance(event.raw_data, dict):
            severity_meta = event.raw_data.get("severity_engine", {}) or {}

        urgency = float(severity_meta.get("composite_urgency", 0.0) or 0.0)
        classification = str(severity_meta.get("classification", ""))
        response_time = severity_meta.get("recommended_response_time")

        logger.info(f"[ALLOCATION] GEOSEARCH for {event.id} ({event.type.value}) "
                    f"@ {event.location.latitude:.4f}, {event.location.longitude:.4f}")

        # Required skill list derived from the event type
        skills_req = CRISIS_SKILL_MAP.get(event.type.value, [])

        # Composite urgency controls search radius and dispatch scale.
        radius_km = 50.0 if urgency < 0.8 else 80.0
        nearby = location_store.get_nearby(
            crisis_lat=event.location.latitude,
            crisis_lon=event.location.longitude,
            radius_km=radius_km,
            skills_required=skills_req,
        )

        if not nearby:
            logger.warning(f"[ALLOCATION] No active volunteers found for {event.id} "
                           f"within {radius_km}km with skills={skills_req}!")
            return

        # GEOSEARCH already returns results sorted nearest-first.
        if urgency > 0:
            multiplier = 2.0 + (urgency * 3.0)
            target_count = max(int(event.skills_required.min_volunteers_needed * multiplier), 5)
        else:
            target_count = max(event.skills_required.min_volunteers_needed * 3, 5)

        dispatched = nearby[:target_count]

        logger.info(
            "[DISPATCH] Crisis %s | urgency=%.3f class=%s response=%s -> %d volunteers",
            event.id,
            urgency,
            classification or "legacy",
            response_time or "n/a",
            len(dispatched),
        )
        for v in dispatched:
            logger.info(f"  → UID={v.user_id} | skills={v.skills}")


allocation_engine = AllocationEngine()
