"""
Firestore dual-write storage for SevaSetu need events.

Schema
------
Collection: need_regions/{geohash}
  Fields (current-state document):
    centroid_lat         float
    centroid_lon         float
    admin_level          str
    event_count          int
    need_scores          map {need_type: float}   ← latest merged score per type
    last_updated         timestamp
    dominant_need        str
    max_severity         str

  Subcollection: need_regions/{geohash}/events/{event_id}
    (append-only time-series log, one doc per event)
    event_id             str
    source               str
    need_type            str
    severity             str
    severity_score       float  ← merged score at write time
    confidence_score     float
    description          str
    timestamp            timestamp
    admin_level          str
    population_affected  int
    source_tier          int
    metadata             map

Usage
-----
  await firestore_store.upsert_region(event, score)  ← update top-level stats
  await firestore_store.append_event(event, score)   ← write time-series entry
  Both calls are idempotent (Firestore merge-set and doc-set with event.id).
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from pipeline.core.schemas import UnifiedIngestionEvent

logger = logging.getLogger(__name__)


class FirestoreStore:
    """Dual-write Firestore storage using the existing firebase_admin SDK."""

    _COLLECTION = "need_regions"

    def __init__(self) -> None:
        self._db = None
        self._firestore = None
        self._init()

    def _init(self) -> None:
        try:
            from firebase_admin import firestore as _fs
            import firebase_admin

            # Use the default app — already initialised in auth.py at boot time
            if firebase_admin._DEFAULT_APP_NAME in firebase_admin._apps:
                self._db = _fs.client()
                self._firestore = _fs
                logger.info("[FirestoreStore] Connected to Firestore ✓")
            else:
                logger.warning("[FirestoreStore] Firebase app not initialised yet — will retry lazily.")
        except Exception as exc:
            logger.error("[FirestoreStore] Init failed: %s", exc)

    def _get_db(self):
        """Lazy init — handles case where firebase_admin isn't ready at import time."""
        if self._db:
            return self._db
        self._init()
        return self._db

    # Public API (async wrappers around sync Firestore calls)
    async def upsert_region(self, event: "UnifiedIngestionEvent", score: float) -> None:
        """
        Merge-update the top-level need_regions/{geohash} document.
        Creates the document if it doesn't exist (set with merge=True).
        """
        db = self._get_db()
        if not db or not event.geohash:
            return

        doc_ref = db.collection(self._COLLECTION).document(event.geohash)

        update_data = {
            "centroid_lat": event.location.latitude,
            "centroid_lon": event.location.longitude,
            "admin_level": event.admin_level,
            "last_updated": self._firestore.SERVER_TIMESTAMP,
            f"need_scores.{event.need_type}": score,
            "dominant_need": event.need_type,
            "max_severity": event.severity,
            # Increment event count atomically
            "event_count": self._firestore.Increment(1),
        }

        try:
            await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: doc_ref.set(update_data, merge=True),
            )
            logger.debug("[FirestoreStore] Upserted region doc: %s", event.geohash)
        except Exception as exc:
            logger.error("[FirestoreStore] upsert_region failed for %s: %s", event.geohash, exc)

    async def append_event(self, event: "UnifiedIngestionEvent", score: float) -> None:
        """
        Write an immutable time-series entry to the events subcollection.
        Document ID = event.id ensures idempotency on re-processing.
        """
        db = self._get_db()
        if not db or not event.geohash:
            return

        sub_ref = (
            db.collection(self._COLLECTION)
            .document(event.geohash)
            .collection("events")
            .document(event.id)
        )

        entry = {
            "event_id":           event.id,
            "source":             event.source,
            "need_type":          event.need_type,
            "severity":           event.severity,
            "severity_score":     score,
            "confidence_score":   event.confidence_score,
            "description":        event.description[:500],   # truncate for storage
            "timestamp":          event.timestamp,
            "admin_level":        event.admin_level,
            "population_affected":event.population_affected,
            "source_tier":        event.source_tier,
            "metadata":           {k: str(v) for k, v in (event.metadata or {}).items()},
        }

        try:
            await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: sub_ref.set(entry),
            )
            logger.debug("[FirestoreStore] Appended event %s → region %s", event.id, event.geohash)
        except Exception as exc:
            logger.error("[FirestoreStore] append_event failed for %s: %s", event.id, exc)

    async def get_region(self, geohash: str) -> dict | None:
        """Read the current-state document for a region. Returns None if absent."""
        db = self._get_db()
        if not db:
            return None
        try:
            doc = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: db.collection(self._COLLECTION).document(geohash).get(),
            )
            return doc.to_dict() if doc.exists else None
        except Exception as exc:
            logger.error("[FirestoreStore] get_region failed for %s: %s", geohash, exc)
            return None


# Global singleton
firestore_store = FirestoreStore()
