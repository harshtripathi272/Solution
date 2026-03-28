import logging
from typing import List

from .pubsub_mock import broker
from .schemas import CrisisEvent
from .location_store import location_store

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
        logger.info(f"[ALLOCATION] GEOSEARCH for {event.id} ({event.type.value}) "
                    f"@ {event.location.latitude:.4f}, {event.location.longitude:.4f}")

        # Required skill list derived from the event type
        skills_req = CRISIS_SKILL_MAP.get(event.type.value, [])

        # Use Redis GEOSEARCH – returns only fresh, consenting volunteers within radius
        radius_km = 50.0
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

        # GEOSEARCH already returns results sorted nearest-first
        target_count = max(event.skills_required.min_volunteers_needed * 3, 5)
        dispatched = nearby[:target_count]

        logger.info(f"[DISPATCH] Routing Crisis {event.id} → {len(dispatched)} volunteers.")
        for v in dispatched:
            logger.info(f"  → UID={v.user_id} | skills={v.skills}")


allocation_engine = AllocationEngine()
