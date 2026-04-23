"""
Redis-backed volunteer location store with GEO indexing.

Architecture:
  - user:{uid}:location  (hash) – metadata: timestamp, skills, consent
  - vol:geo_index         (Redis sorted set via GEOADD) – spatial index

TTL: 2 hours per user key for automatic privacy-safe data expiry.
"""

import json
import logging
import time
from datetime import datetime, timezone
from math import radians, sin, cos, sqrt, atan2
from typing import List, Optional

import redis

logger = logging.getLogger(__name__)

GEO_INDEX_KEY = "vol:geo_index"
LOCATION_TTL   = 7200     # 2 hours in seconds
MIN_UPDATE_GAP = 5        # Rate-limit: reject updates faster than 5 seconds
MAX_LAT, MIN_LAT = 90.0, -90.0
MAX_LON, MIN_LON = 180.0, -180.0


class VolunteerLocation:
    """Lightweight dataclass for results coming back from Redis."""
    def __init__(self, user_id: str, lat: float, lon: float,
                 timestamp: datetime, skills: List[str]):
        self.user_id   = user_id
        self.lat       = lat
        self.lon       = lon
        self.timestamp = timestamp
        self.skills    = skills


class RedisLocationStore:
    def __init__(self, host: str = "localhost", port: int = 6379, db: int = 0):
        # socket_timeout prevents indefinite blocking when Redis is unavailable on startup.
        self.redis = redis.Redis(host=host, port=port, db=db,
                                 decode_responses=True,
                                 socket_connect_timeout=2,
                                 socket_timeout=2)
        # Removed synchronous .ping() to prevent 28s Windows IPv6 TCP timeout 
        # when Redis is unavailable during module import.
        logger.info("[LocationStore] Redis initialized (lazy connect).")

    #  Write path                                                          
    def update_location(self, user_id: str, lat: float, lon: float,
                        timestamp: datetime, skills: List[str] = None) -> bool:
        """
        Stores the latest volunteer location. Returns False if:
         - Redis is down
         - Coordinates are invalid
         - Update was sent too soon (rate limit)
        """
        if not self.redis:
            return False

        # 1. Validate coordinate ranges
        if not (MIN_LAT <= lat <= MAX_LAT and MIN_LON <= lon <= MAX_LON):
            logger.warning(f"[LocationStore] Invalid coords ({lat}, {lon}) for {user_id}")
            return False

        user_key = f"user:{user_id}:location"

        # 2. Rate-limit: reject if last update was within MIN_UPDATE_GAP seconds
        existing = self.redis.hget(user_key, "ts_epoch")
        if existing:
            elapsed = time.time() - float(existing)
            if elapsed < MIN_UPDATE_GAP:
                logger.debug(f"[LocationStore] Throttled update from {user_id} ({elapsed:.1f}s < {MIN_UPDATE_GAP}s)")
                return False

        # 3. Write metadata hash with TTL
        ts_epoch = timestamp.timestamp() if timestamp else time.time()
        self.redis.hset(user_key, mapping={
            "lat":      lat,
            "lon":      lon,
            "ts_epoch": ts_epoch,
            "skills":   json.dumps(skills or []),
        })
        self.redis.expire(user_key, LOCATION_TTL)

        # 4. Update GEO index (lon, lat order for Redis)
        self.redis.geoadd(GEO_INDEX_KEY, [lon, lat, user_id])
        # GEO index does not support TTL per member; stale members are filtered
        # in the read path by checking the metadata TTL.
        logger.debug(f"[LocationStore] Updated {user_id}: ({lat:.5f}, {lon:.5f})")
        return True

    #  Read path                                                           
    def get_nearby(self, crisis_lat: float, crisis_lon: float,
                   radius_km: float = 10.0,
                   skills_required: List[str] = None) -> List[VolunteerLocation]:
        """
        Uses Redis GEOSEARCH to find volunteers within radius_km, then filters by:
          - timestamp freshness (within 2 hours)
          - optional skill requirements
        """
        if not self.redis:
            return []

        try:
            # GEOSEARCH: unit = km, BYRADIUS around crisis coordinates
            nearby_ids = self.redis.geosearch(
                GEO_INDEX_KEY,
                longitude=crisis_lon,
                latitude=crisis_lat,
                radius=radius_km,
                unit="km",
                sort="ASC",       # closest first
                count=200,        # cap to prevent runaway queries
            )
        except Exception as e:
            logger.error(f"[LocationStore] GEOSEARCH failed: {e}")
            return []

        results = []
        cutoff_epoch = time.time() - LOCATION_TTL

        for uid in nearby_ids:
            user_key = f"user:{uid}:location"
            data = self.redis.hgetall(user_key)

            if not data:
                # Key has expired (user inactive > 2 hours) – skip
                self.redis.zrem(GEO_INDEX_KEY, uid)
                continue

            try:
                ts_epoch = float(data.get("ts_epoch", 0))
            except (TypeError, ValueError):
                logger.warning(f"[LocationStore] Invalid timestamp for {uid}; dropping stale entry")
                self.redis.delete(user_key)
                self.redis.zrem(GEO_INDEX_KEY, uid)
                continue

            if ts_epoch < cutoff_epoch:
                # Stale but key not yet evicted – treat as inactive
                continue

            try:
                skills = json.loads(data.get("skills", "[]"))
                if not isinstance(skills, list):
                    skills = []
            except Exception:
                skills = []

            try:
                lat_val = float(data["lat"])
                lon_val = float(data["lon"])
            except (KeyError, TypeError, ValueError):
                logger.warning(f"[LocationStore] Invalid coordinates for {uid}; dropping entry")
                self.redis.delete(user_key)
                self.redis.zrem(GEO_INDEX_KEY, uid)
                continue

            # Optional skills filter
            if skills_required:
                if not all(s in skills for s in skills_required):
                    continue

            ts = datetime.fromtimestamp(ts_epoch, tz=timezone.utc)
            results.append(VolunteerLocation(
                user_id=uid,
                lat=lat_val,
                lon=lon_val,
                timestamp=ts,
                skills=skills,
            ))

        return results

    def get_user_location(self, user_id: str) -> Optional[VolunteerLocation]:
        """Returns the latest shared location for a user, if still fresh."""
        if not self.redis:
            return None

        user_key = f"user:{user_id}:location"
        data = self.redis.hgetall(user_key)
        if not data:
            return None

        try:
            ts_epoch = float(data.get("ts_epoch", 0))
            lat_val = float(data["lat"])
            lon_val = float(data["lon"])
        except (KeyError, TypeError, ValueError):
            return None

        if ts_epoch < (time.time() - LOCATION_TTL):
            return None

        try:
            skills = json.loads(data.get("skills", "[]"))
            if not isinstance(skills, list):
                skills = []
        except Exception:
            skills = []

        return VolunteerLocation(
            user_id=user_id,
            lat=lat_val,
            lon=lon_val,
            timestamp=datetime.fromtimestamp(ts_epoch, tz=timezone.utc),
            skills=skills,
        )

    def remove_user(self, user_id: str):
        """Called when a volunteer explicitly disables location sharing."""
        if not self.redis:
            return
        self.redis.delete(f"user:{user_id}:location")
        self.redis.zrem(GEO_INDEX_KEY, user_id)
        logger.info(f"[LocationStore] Removed location consent for {user_id}")


# Global singleton
location_store = RedisLocationStore()
