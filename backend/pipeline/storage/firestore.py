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
    latest_event_id      str
    latest_event_source  str
    latest_text_preview  str   ← first ~100 chars from incoming stream text

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

Collection: document_registry/{sha256_hash}
    Fields:
        source_ngo            str
        pdf_url               str
        publication_date      timestamp | null
        first_seen_at         timestamp
        last_seen_at          timestamp
        status                str (processed | failed | unreachable)
        failure_reason        str | null
        extraction_version    int
"""

from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timezone
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from pipeline.core.schemas import UnifiedIngestionEvent, DocumentMetadata

logger = logging.getLogger(__name__)


def _preview_text(event: "UnifiedIngestionEvent", limit: int = 100) -> str:
    """Compact preview of incoming text for quick pipeline observability."""
    raw = (event.description or "").strip()
    if not raw:
        raw = str((event.metadata or {}).get("description", "")).strip()
    compact = " ".join(raw.split())
    return compact[:limit]


class FirestoreStore:
    """Dual-write Firestore storage using the existing firebase_admin SDK."""

    _COLLECTION = "need_regions"
    _DOCUMENT_REGISTRY_COLLECTION = "document_registry"

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
        if not db:
            logger.warning(
                "[FirestoreStore] Skipping upsert_region for %s: Firestore client not ready",
                event.id,
            )
            return
        if not event.geohash:
            logger.warning(
                "[FirestoreStore] Skipping upsert_region for %s: missing geohash",
                event.id,
            )
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
            "latest_event_id": event.id,
            "latest_event_source": event.source,
            "latest_text_preview": _preview_text(event, limit=100),
            # Increment event count atomically
            "event_count": self._firestore.Increment(1),
        }

        try:
            await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: doc_ref.set(update_data, merge=True),
            )
            logger.info(
                "[FirestoreStore] Upserted need_regions/%s from event %s",
                event.geohash,
                event.id,
            )
        except Exception as exc:
            logger.error("[FirestoreStore] upsert_region failed for %s: %s", event.geohash, exc)

    async def append_event(self, event: "UnifiedIngestionEvent", score: float) -> None:
        """
        Write an immutable time-series entry to the events subcollection.
        Document ID = event.id ensures idempotency on re-processing.
        """
        db = self._get_db()
        if not db:
            logger.warning(
                "[FirestoreStore] Skipping append_event for %s: Firestore client not ready",
                event.id,
            )
            return
        if not event.geohash:
            logger.warning(
                "[FirestoreStore] Skipping append_event for %s: missing geohash",
                event.id,
            )
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
            logger.info(
                "[FirestoreStore] Appended need_regions/%s/events/%s",
                event.geohash,
                event.id,
            )
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

    async def is_document_hash_processed(self, sha256_hash: str) -> bool:
        """Check whether a document hash is already present in the registry."""
        db = self._get_db()
        if not db or not sha256_hash:
            return False
        try:
            doc = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: db.collection(self._DOCUMENT_REGISTRY_COLLECTION).document(sha256_hash).get(),
            )
            return bool(doc.exists)
        except Exception as exc:
            logger.error("[FirestoreStore] is_document_hash_processed failed for %s: %s", sha256_hash, exc)
            return False

    async def upsert_document_registry(
        self,
        metadata: "DocumentMetadata",
        status: str = "processed",
        failure_reason: str | None = None,
        extraction_version: int = 1,
    ) -> None:
        """Register or update a document hash entry for dedup and incremental refresh."""
        db = self._get_db()
        if not db or not metadata.sha256_hash:
            return

        now = datetime.now(timezone.utc)
        doc_ref = db.collection(self._DOCUMENT_REGISTRY_COLLECTION).document(metadata.sha256_hash)
        payload = {
            "source_ngo": metadata.source_ngo,
            "pdf_url": metadata.pdf_url,
            "publication_date": metadata.publication_date,
            "last_seen_at": now,
            "status": status,
            "failure_reason": failure_reason,
            "extraction_version": extraction_version,
        }

        try:
            await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: doc_ref.set(
                    {
                        **payload,
                        "first_seen_at": self._firestore.SERVER_TIMESTAMP,
                    },
                    merge=True,
                ),
            )
            logger.debug("[FirestoreStore] Upserted document_registry for %s", metadata.sha256_hash)
        except Exception as exc:
            logger.error("[FirestoreStore] upsert_document_registry failed for %s: %s", metadata.sha256_hash, exc)


# Global singleton
firestore_store = FirestoreStore()
