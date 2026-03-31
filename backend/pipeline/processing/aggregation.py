"""
Aggregation layer — deduplication + weighted score merging.

Responsibilities:
  1. DEDUPLICATION: Detect if an equivalent event has already been
     processed today (same source + region + need_type + date).
     Uses a Redis set with a 24-hour TTL as the dedup store.

  2. SCORE MERGING: Combine the incoming event's severity into the
     existing regional need score via exponential weighted average:

       new_score = alpha * incoming_score + (1 - alpha) * existing_score

     where alpha is determined by:
       alpha = confidence_score * recency_weight
       recency_weight = 1.0 for events in the last 1 h,
                        decaying to 0.1 after 24 h.

  3. RETURNS: A (is_duplicate: bool, merged_score: float) tuple so the
     caller can decide whether to write to storage.

No external service calls — only Redis (already available).
Gracefully skips dedup tracking when Redis is unavailable.
"""

from __future__ import annotations

import hashlib
import logging
import time
from datetime import datetime, timezone
from typing import Tuple

logger = logging.getLogger(__name__)


# Constants

_DEDUP_TTL_SECONDS = 86400       # 24 hours
_SCORE_TTL_SECONDS = 3600        # how long a regional score lives in Redis
_DEDUP_KEY_PREFIX  = "dedup"     # dedup:{date_str}:{event_hash}
_SCORE_KEY_PREFIX  = "score"     # score:{geohash}:{need_type}

# Severity → raw numeric score mapping
_SEVERITY_SCORES = {
    "critical": 1.00,
    "red":      1.00,
    "high":     0.70,
    "orange":   0.70,
    "moderate": 0.40,
    "green":    0.40,
    "low":      0.20,
    "unknown":  0.10,
}


# Aggregation layer class
class AggregationLayer:
    """
    Stateless aggregation helper.  Accepts the shared Redis client from
    location_store so we don't open a second connection.
    """

    def __init__(self) -> None:
        self._redis = None
        self._init_redis()

    def _init_redis(self) -> None:
        try:
            from pipeline.storage.location import location_store
            self._redis = location_store.redis  # may be None if Redis is down
        except Exception as exc:
            logger.warning("[Aggregation] Could not access Redis: %s", exc)

    # Public API
    def event_score(self, severity: str, confidence: float) -> float:
        """Map severity label + confidence into a 0–1 need score."""
        base = _SEVERITY_SCORES.get(severity.lower(), 0.10)
        return round(base * confidence, 4)

    def process(
        self,
        event_id: str,
        source: str,
        geohash: str,
        need_type: str,
        timestamp: datetime,
        severity: str,
        confidence: float,
    ) -> Tuple[bool, float]:
        """
        Check dedup + compute merged score.

        Returns
        -------
        (is_duplicate, merged_score)
          is_duplicate : True  → skip storage writes
          merged_score : float → weighted score to persist
        """
        # 1. Compute deterministic dedup key
        dedup_hash = self._make_dedup_hash(source, geohash, need_type, timestamp)
        if self._is_duplicate(dedup_hash, timestamp):
            logger.debug("[Aggregation] Duplicate event skipped: key=%s", dedup_hash)
            return (True, 0.0)

        # 2. Register as seen
        self._register(dedup_hash, timestamp)

        # 3. Compute incoming score
        incoming = self.event_score(severity, confidence)

        # 4. Merge with existing regional score
        existing = self._get_existing_score(geohash, need_type)
        recency_w = self._recency_weight(timestamp)
        alpha = confidence * recency_w
        merged = round(alpha * incoming + (1 - alpha) * existing, 4)

        # 5. Persist merged score for future merges (short TTL — storage layer
        #    will write the authoritative value to Firestore/BQ/Redis cache)
        self._set_score(geohash, need_type, merged)

        logger.debug(
            "[Aggregation] geohash=%s need=%s incoming=%.3f existing=%.3f "
            "alpha=%.3f merged=%.3f",
            geohash, need_type, incoming, existing, alpha, merged,
        )
        return (False, merged)

    # Dedup helpers
    @staticmethod
    def _make_dedup_hash(source: str, geohash: str, need_type: str, ts: datetime) -> str:
        date_str = ts.strftime("%Y-%m-%d")
        raw = f"{source}|{geohash}|{need_type}|{date_str}"
        return hashlib.sha256(raw.encode()).hexdigest()[:16]

    def _dedup_key(self, dedup_hash: str, ts: datetime) -> str:
        date_str = ts.strftime("%Y-%m-%d")
        return f"{_DEDUP_KEY_PREFIX}:{date_str}:{dedup_hash}"

    def _is_duplicate(self, dedup_hash: str, ts: datetime) -> bool:
        if not self._redis:
            return False   # can't check — allow through
        try:
            key = self._dedup_key(dedup_hash, ts)
            return bool(self._redis.exists(key))
        except Exception as exc:
            logger.warning("[Aggregation] Dedup check failed: %s", exc)
            return False

    def _register(self, dedup_hash: str, ts: datetime) -> None:
        if not self._redis:
            return
        try:
            key = self._dedup_key(dedup_hash, ts)
            self._redis.set(key, "1", ex=_DEDUP_TTL_SECONDS)
        except Exception as exc:
            logger.warning("[Aggregation] Dedup register failed: %s", exc)

    # Score helpers
    def _score_key(self, geohash: str, need_type: str) -> str:
        return f"{_SCORE_KEY_PREFIX}:{geohash}:{need_type}"

    def _get_existing_score(self, geohash: str, need_type: str) -> float:
        if not self._redis:
            return 0.0
        try:
            val = self._redis.get(self._score_key(geohash, need_type))
            return float(val) if val else 0.0
        except Exception:
            return 0.0

    def _set_score(self, geohash: str, need_type: str, score: float) -> None:
        if not self._redis:
            return
        try:
            self._redis.set(self._score_key(geohash, need_type), score, ex=_SCORE_TTL_SECONDS)
        except Exception as exc:
            logger.warning("[Aggregation] Score set failed: %s", exc)

    @staticmethod
    def _recency_weight(ts: datetime) -> float:
        """1.0 for events <1 h old, decaying linearly to 0.1 at 24 h."""
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)
        age_hours = (datetime.now(timezone.utc) - ts).total_seconds() / 3600
        age_hours = max(0.0, min(age_hours, 24.0))
        # Linear decay: 1.0 at 0 h → 0.1 at 24 h
        return round(1.0 - (0.9 * age_hours / 24.0), 4)


# Global singleton
aggregation_layer = AggregationLayer()
