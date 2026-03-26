import logging
from typing import List, Dict

from .pubsub_mock import broker
from .schemas import CrisisEvent, SkillMatrix
from .validation_service import ValidationService
from .location_store import location_store

logger = logging.getLogger(__name__)

class AllocationEngine:
    def start(self):
        # We listen to Tier 1 and verified Tier 2 events
        broker.subscribe("official-alerts", "volunteer-allocator", self._handle_crisis)
        broker.subscribe("verified-crisis", "volunteer-allocator", self._handle_crisis)
        logger.info("Volunteer Allocation Engine running. Ready to dispatch.")

    async def _handle_crisis(self, event: CrisisEvent):
        logger.info(f"[ALLOCATION] Beginning volunteer matching for {event.id} ({event.type.value})")
        
        # We pull active streaming volunteers from the strict TTL in-memory cache
        # Rather than querying static, outdated database profiles
        active_volunteers = location_store.get_all_active_locations()
        
        matched_volunteers = []
        for v in active_volunteers:
            dist_km = ValidationService._haversine(
                event.location.latitude, event.location.longitude,
                v.lat, v.lon
            )
            
            # Broad search radius: 50km
            if dist_km <= 50.0:
                # Skills check
                if self._check_skills(event.skills_required, v.skills):
                    matched_volunteers.append({
                        "uid": v.user_id,
                        "dist": dist_km,
                        "data": {"skills": v.skills}
                    })
                    
        if not matched_volunteers:
            logger.warning(f"[ALLOCATION] No available volunteers found for {event.id} within 50km!")
            return
            
        # Sort by closest first
        matched_volunteers.sort(key=lambda x: x["dist"])
        
        # Dispatch logic (Top N * 3 to guarantee minimum response fill rate)
        target_count = event.skills_required.min_volunteers_needed * 3
        dispatched = matched_volunteers[:target_count]
        
        logger.info(f"[DISPATCH] Routed Crisis {event.id} to {len(dispatched)} volunteers.")
        for v in dispatched:
            logger.info(f" -> Sending Push Notification to Volunteer {v['uid']} ({v['dist']:.1f}km away)")

    def _check_skills(self, required: SkillMatrix, user_skills: List[str]) -> bool:
        if required.requires_medical and "medical" not in user_skills: return False
        if required.requires_rescue and "rescue" not in user_skills: return False
        if required.requires_logistics and "logistics" not in user_skills: return False
        if required.requires_counseling and "counseling" not in user_skills: return False
        return True

# Global Instance
allocation_engine = AllocationEngine()
