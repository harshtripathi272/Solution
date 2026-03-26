import time
import logging
from typing import Dict, List, Optional
from pydantic import BaseModel
from datetime import datetime, timezone

logger = logging.getLogger(__name__)

class VolunteerLocation(BaseModel):
    user_id: str
    lat: float
    lon: float
    geohash: str
    timestamp: datetime
    skills: List[str] = [] # Cached skills to prevent DB lookups during allocation
    
class InMemoryLocationStore:
    """
    Simulates a fast Redis key-value store with TTL expirations for Phase 1/2.
    Stores only the absolute latest location per volunteer for strict privacy.
    """
    def __init__(self, ttl_seconds: int = 7200): # Default 2 hours TTL
        self.store: Dict[str, VolunteerLocation] = {}
        self.ttl_seconds = ttl_seconds

    def _encode_geohash(self, lat: float, lon: float, precision: int = 5) -> str:
        # A simple placeholder geohash implementation if a dedicated library isn't available
        # In production, use `python-geohash` or `pygeohash`
        return f"{lat:.2f},{lon:.2f}" 

    def update_location(self, user_id: str, lat: float, lon: float, timestamp: datetime, skills: List[str] = None):
        logger.debug(f"[LocationStore] Updating location for {user_id}: {lat}, {lon}")
        
        # Merge skills if already exists
        current_skills = skills or []
        if not current_skills and user_id in self.store:
            current_skills = self.store[user_id].skills
            
        loc = VolunteerLocation(
            user_id=user_id,
            lat=lat,
            lon=lon,
            geohash=self._encode_geohash(lat, lon),
            timestamp=timestamp,
            skills=current_skills
        )
        self.store[user_id] = loc

    def get_all_active_locations(self) -> List[VolunteerLocation]:
        """Returns all volunteers whose location ping was within the TTL window"""
        self._cleanup_expired()
        return list(self.store.values())

    def _cleanup_expired(self):
        """Evicts stale location data to enforce Data Minimization & Privacy"""
        now = datetime.now(timezone.utc)
        expired_keys = []
        for uid, loc in self.store.items():
            # Handle naive datetime from pydantic conversions if necessary
            loc_time = loc.timestamp.replace(tzinfo=timezone.utc) if not loc.timestamp.tzinfo else loc.timestamp
            if (now - loc_time).total_seconds() > self.ttl_seconds:
                expired_keys.append(uid)
                
        for key in expired_keys:
            logger.info(f"[LocationStore] Evicting stale location for {key} (> 2 hours inactive)")
            del self.store[key]

# Global singleton
location_store = InMemoryLocationStore()
