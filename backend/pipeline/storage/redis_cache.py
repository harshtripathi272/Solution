"""
Redis need-score cache.

Provides low-latency (sub-millisecond) lookups for the allocation engine
and need analysis layer, bypassing Firestore/BigQuery for hot reads.

Key pattern:
  region:{geohash}:{need_type}
    VALUE : JSON  { "score": float, "source_count": int, "updated_at": ISO str }
    TTL   : 1 hour (3600 s)  — refreshed on every write

Usage
-----
  redis_need_cache.set("ttnyz", "flood", 0.82)
  data = redis_need_cache.get("ttnyz", "flood")  # → {"score": 0.82, ...}
  all_scores = redis_need_cache.get_all_for_region("ttnyz")  # → {"flood": 0.82, ...}

Shares the same Redis connection as RedisLocationStore (imported lazily).
Falls back gracefully to no-ops when Redis is unavailable.
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, timezone
from typing import Dict, Optional

logger = logging.getLogger(__name__)

_KEY_PREFIX = "region"
_CACHE_TTL  = 3600   # 1 hour


class RedisNeedCache:
    """Need-score cache backed by the existing Redis instance."""

    def __init__(self) -> None:
        self._redis = None
        self._init()

    def _init(self) -> None:
        try:
            from pipeline.storage.location import location_store
            self._redis = location_store.redis
            if self._redis:
                logger.info("[NeedCache] Redis need cache ready ✓")
            else:
                logger.warning("[NeedCache] Redis unavailable — cache disabled.")
        except Exception as exc:
            logger.warning("[NeedCache] Could not access Redis: %s", exc)
    #Write
    def set(self, geohash: str, need_type: str, score: float, source_count: int = 1) -> None:
        """Cache a regional need score. Extends TTL on every write."""
        if not self._redis or not geohash:
            return
        key = self._make_key(geohash, need_type)
        value = json.dumps({
            "score":        round(score, 4),
            "source_count": source_count,
            "updated_at":   datetime.now(timezone.utc).isoformat(),
        })
        try:
            self._redis.set(key, value, ex=_CACHE_TTL)
            logger.debug("[NeedCache] SET %s = %.4f", key, score)
        except Exception as exc:
            logger.warning("[NeedCache] set failed for %s: %s", key, exc)

    def increment_source_count(self, geohash: str, need_type: str) -> None:
        """Atomically bump the source_count for an existing cache entry."""
        data = self.get(geohash, need_type)
        if data:
            self.set(geohash, need_type, data["score"], data.get("source_count", 1) + 1)
    #Read
    def get(self, geohash: str, need_type: str) -> Optional[Dict]:
        """
        Return cached dict { score, source_count, updated_at } or None.
        """
        if not self._redis or not geohash:
            return None
        key = self._make_key(geohash, need_type)
        try:
            raw = self._redis.get(key)
            return json.loads(raw) if raw else None
        except Exception as exc:
            logger.warning("[NeedCache] get failed for %s: %s", key, exc)
            return None

    def get_score(self, geohash: str, need_type: str) -> float:
        """Convenience — returns just the score float (0.0 if absent)."""
        data = self.get(geohash, need_type)
        return float(data["score"]) if data else 0.0

    def get_all_for_region(self, geohash: str) -> Dict[str, float]:
        """
        Scan all need_type keys for a geohash, returning {need_type: score}.
        Uses Redis SCAN to avoid blocking; capped at 50 entries per region.
        """
        if not self._redis or not geohash:
            return {}
        pattern = f"{_KEY_PREFIX}:{geohash}:*"
        result: Dict[str, float] = {}
        try:
            cursor = 0
            scanned = 0
            while scanned < 50:
                cursor, keys = self._redis.scan(cursor, match=pattern, count=10)
                for k in keys:
                    raw = self._redis.get(k)
                    if raw:
                        data = json.loads(raw)
                        # Extract need_type from key suffix
                        need_type = k.split(":")[-1]
                        result[need_type] = float(data.get("score", 0.0))
                    scanned += 1
                if cursor == 0:
                    break
        except Exception as exc:
            logger.warning("[NeedCache] get_all_for_region failed for %s: %s", geohash, exc)
        return result

    def invalidate(self, geohash: str, need_type: str) -> None:
        """Explicitly remove a cache entry (e.g., after a region is resolved)."""
        if not self._redis:
            return
        try:
            self._redis.delete(self._make_key(geohash, need_type))
        except Exception:
            pass

    # Helpers
    @staticmethod
    def _make_key(geohash: str, need_type: str) -> str:
        return f"{_KEY_PREFIX}:{geohash}:{need_type}"


# Global singleton
redis_need_cache = RedisNeedCache()
