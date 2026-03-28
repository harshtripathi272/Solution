import asyncio
import logging
from typing import List
from datetime import datetime, timezone
from math import radians, sin, cos, sqrt, atan2

from pipeline.core.pubsub import broker
from pipeline.core.schemas import CrisisEvent

logger = logging.getLogger(__name__)

class ValidationService:
    def __init__(self):
        # Cache of official alerts for cross-referencing (in memory for Phase 1)
        self.official_cache: List[CrisisEvent] = []
        
    def start(self):
        # Listen to official alerts to build our ground-truth cache
        broker.subscribe("official-alerts", "validation-cache-updater", self._handle_official_alert)
        # Listen to unverified tier 2 topics
        broker.subscribe("citizen-reports", "validation-checker", self._verify_report)
        broker.subscribe("social-media-raw", "validation-checker", self._verify_report)
        logger.info("Validation Service online. Ready to cross-reference Tier 2 inputs.")

    async def _handle_official_alert(self, event: CrisisEvent):
        """Stores official alerts for 24 hours to cross-reference against crowd data"""
        self.official_cache.append(event)
        # Cleanup old events
        try:
            now = datetime.now(timezone.utc)
            # Make timestamp aware if it isn't
            self.official_cache = [e for e in self.official_cache 
                                   if e.timestamp.tzinfo and (now - e.timestamp).total_seconds() < 86400]
        except Exception as e:
            logger.error(f"Error cleaning cache: {e}")

    async def _verify_report(self, event: CrisisEvent):
        """Cross references a tier-2 event against official cache using 10km/2hr fuzzy matching"""
        if self._is_fuzzy_match(event):
            event.is_verified = True
            logger.info(f"[VALIDATED] Event {event.id} verified via cross-reference. Routing to verified-crisis.")
            await broker.publish("verified-crisis", event)
        else:
            logger.debug(f"[UNVERIFIED] Event {event.id} could not be verified yet. Holding in unverified state.")
            # In a real system, we might hold this in a buffer waiting for more unverified reports to form a consensus.

    def _is_fuzzy_match(self, unverified: CrisisEvent) -> bool:
        if not unverified.timestamp.tzinfo:
            return False
            
        for official in self.official_cache:
            if official.type != unverified.type:
                continue
            
            if not official.timestamp.tzinfo:
                continue
                
            # Temporal check (within 2 hours)
            time_diff = abs((official.timestamp - unverified.timestamp).total_seconds())
            if time_diff > 7200: # 2 hours
                continue
                
            # Spatial check (Haversine formula for 10km)
            dist_km = self._haversine(
                official.location.latitude, official.location.longitude,
                unverified.location.latitude, unverified.location.longitude
            )
            if dist_km <= 10.0:
                logger.info(f"Fuzzy Match Found! Distance: {dist_km:.2f}km, Temporal diff: {time_diff}s")
                return True
                
        return False

    @staticmethod
    def _haversine(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        """Calculate the great circle distance in kilometers between two points on the earth."""
        R = 6371.0 # Earth radius in kilometers
        dlat = radians(lat2 - lat1)
        dlon = radians(lon2 - lon1)
        a = sin(dlat / 2)**2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon / 2)**2
        c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c

# Global instance
validation_service = ValidationService()
