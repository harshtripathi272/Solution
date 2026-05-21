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
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import TYPE_CHECKING, Any
from dotenv import load_dotenv

load_dotenv()

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
    _CHRONIC_COLLECTION = "chronic_scores"
    _COMMUNITY_PROFILES_COLLECTION = "community_profiles"
    _COMMUNITY_HISTORY_COLLECTION = "community_historical_context"
    _VOLUNTEER_TASKS_COLLECTION = "volunteer_area_tasks"
    _PIPELINE_ALERTS_COLLECTION = "pipeline_alerts"
    _SEVERITY_FEEDBACK_COLLECTION = "severity_feedback"

    def __init__(self) -> None:
        self._db = None
        self._firestore = None
        self._init_attempted = False
        self._init_error: str | None = None
        # NOTE: _init() is intentionally NOT called here.
        # The gRPC connection is established lazily on first database access
        # to avoid a ~5 second blocking call during module import / uvicorn startup.

    @staticmethod
    def _resolve_credentials_path(raw_path: str | None) -> Path | None:
        if not raw_path:
            return None

        candidate = Path(raw_path)
        if candidate.is_absolute() and candidate.exists():
            return candidate

        backend_dir = Path(__file__).resolve().parents[2]
        candidates = [
            Path.cwd() / raw_path,
            backend_dir / raw_path,
            backend_dir / candidate.name,
        ]
        for path in candidates:
            if path.exists():
                return path
        return None

    def _init(self, force: bool = False) -> None:
        if self._db is not None and not force:
            return
        if self._init_attempted and not force and self._db is None:
            return

        self._init_attempted = True
        try:
            from firebase_admin import firestore as _fs
            from firebase_admin import credentials as _credentials
            import firebase_admin

            if firebase_admin._DEFAULT_APP_NAME not in firebase_admin._apps:
                # Prefer explicit service-account credentials when available.
                cred_path = self._resolve_credentials_path(
                    os.getenv("FIREBASE_CREDENTIALS_PATH")
                    or os.getenv("GOOGLE_APPLICATION_CREDENTIALS")
                )
                if cred_path is not None:
                    firebase_admin.initialize_app(_credentials.Certificate(str(cred_path)))
                    logger.info("[FirestoreStore] Initialized Firebase app using credentials at %s", cred_path)
                else:
                    # Last-resort ADC init. If ADC is not configured, this will raise.
                    firebase_admin.initialize_app()
                    logger.info("[FirestoreStore] Initialized Firebase app using Application Default Credentials")

            self._db = _fs.client()
            self._firestore = _fs
            self._init_error = None
            logger.info("[FirestoreStore] Connected to Firestore ✓")
        except Exception as exc:
            self._db = None
            self._firestore = None
            self._init_error = str(exc)
            logger.error("[FirestoreStore] Init failed: %s", exc)

    def _get_db(self):
        """Resolve Firestore client once; fail fast when unavailable."""
        if self._db:
            return self._db

        if not self._init_attempted:
            self._init()

        if self._db is None and self._init_error:
            logger.debug("[FirestoreStore] Firestore unavailable: %s", self._init_error)
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

        severity_engine = (event.metadata or {}).get("severity_engine", {})
        update_data = {
            "centroid_lat": event.location.latitude,
            "centroid_lon": event.location.longitude,
            "admin_level": event.admin_level,
            "last_updated": self._firestore.SERVER_TIMESTAMP,
            f"need_scores.{event.need_type}": score,
            "dominant_need": event.need_type,
            "max_severity": event.severity,
            "composite_urgency": severity_engine.get("composite_urgency", score),
            "severity_classification": severity_engine.get("classification"),
            "recommended_response_time": severity_engine.get("recommended_response_time"),
            "latest_event_id": event.id,
            "latest_event_source": event.source,
            "latest_text_preview": _preview_text(event, limit=100),
            # Increment event count atomically
            "event_count": self._firestore.Increment(1),
            "severity_history": self._firestore.ArrayUnion([
                {
                    "timestamp": event.timestamp,
                    "score": severity_engine.get("composite_urgency", score),
                    "classification": severity_engine.get("classification", "Moderate"),
                }
            ]),
            "organization_id": (event.metadata or {}).get("organization_id", "GLOBAL"),
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

        severity_engine = (event.metadata or {}).get("severity_engine", {})
        entry = {
            "event_id":           event.id,
            "source":             event.source,
            "need_type":          event.need_type,
            "severity":           event.severity,
            "severity_score":     score,
            "severity_acute":     severity_engine.get("severity_acute"),
            "severity_chronic":   severity_engine.get("severity_chronic"),
            "composite_urgency":  severity_engine.get("composite_urgency", score),
            "reliability_score":  severity_engine.get("reliability_score"),
            "classification":     severity_engine.get("classification"),
            "recommended_response_time": severity_engine.get("recommended_response_time"),
            "severity_explanation": severity_engine.get("explanation"),
            "confidence_score":   event.confidence_score,
            "description":        event.description[:500],   # truncate for storage
            "timestamp":          event.timestamp,
            "admin_level":        event.admin_level,
            "population_affected":event.population_affected,
            "source_tier":        event.source_tier,
            "organization_id":   (event.metadata or {}).get("organization_id", "GLOBAL"),
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

    async def upsert_chronic_score(self, event: "UnifiedIngestionEvent", severity_payload: dict) -> None:
        """
        Persists chronic score snapshots with TTL-friendly expires_at field.
        Firestore TTL indexing should be configured on chronic_scores.expires_at.
        """
        db = self._get_db()
        if not db:
            return

        geohash = event.geohash or ""
        if not geohash:
            return

        chronic_score = float(severity_payload.get("severity_chronic", 0.0) or 0.0)
        if chronic_score <= 0.0:
            return

        from datetime import timedelta

        doc_id = f"{geohash}:{event.need_type}"
        doc_ref = db.collection(self._CHRONIC_COLLECTION).document(doc_id)
        expires_at = datetime.now(timezone.utc) + timedelta(days=180)

        payload = {
            "geohash": geohash,
            "need_type": event.need_type,
            "severity_chronic": chronic_score,
            "source": event.source,
            "last_event_id": event.id,
            "updated_at": datetime.now(timezone.utc),
            "expires_at": expires_at,
        }

        try:
            await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: doc_ref.set(payload, merge=True),
            )
        except Exception as exc:
            logger.error("[FirestoreStore] upsert_chronic_score failed for %s: %s", doc_id, exc)

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

    async def create_pipeline_alert(
        self,
        event_id: str,
        stage: str,
        message: str,
        details: dict | None = None,
        severity: str = "error",
    ) -> None:
        db = self._get_db()
        if not db:
            return
        payload = {
            "event_id": event_id,
            "stage": stage,
            "message": message,
            "details": details or {},
            "severity": severity,
            "created_at": datetime.now(timezone.utc),
            "status": "open",
        }
        try:
            await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: db.collection(self._PIPELINE_ALERTS_COLLECTION).add(payload),
            )
        except Exception as exc:
            logger.error("[FirestoreStore] create_pipeline_alert failed for %s: %s", event_id, exc)

    async def upsert_severity_feedback(
        self,
        geohash: str,
        need_type: str,
        feedback: str,
        note: str,
        actor_uid: str,
    ) -> None:
        db = self._get_db()
        if not db or not geohash:
            return
        doc_id = f"{geohash}:{need_type}"
        payload = {
            "geohash": geohash,
            "need_type": need_type,
            "feedback": feedback,
            "note": note,
            "actor_uid": actor_uid,
            "updated_at": datetime.now(timezone.utc),
        }
        try:
            await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: db.collection(self._SEVERITY_FEEDBACK_COLLECTION).document(doc_id).set(payload, merge=True),
            )
        except Exception as exc:
            logger.error("[FirestoreStore] upsert_severity_feedback failed for %s: %s", doc_id, exc)

    async def get_severity_feedback(self, geohash: str, need_type: str) -> str | None:
        db = self._get_db()
        if not db or not geohash:
            return None
        doc_id = f"{geohash}:{need_type}"
        try:
            doc = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: db.collection(self._SEVERITY_FEEDBACK_COLLECTION).document(doc_id).get(),
            )
            if not doc.exists:
                return None
            data = doc.to_dict() or {}
            feedback = str(data.get("feedback", "")).strip().lower()
            return feedback or None
        except Exception as exc:
            logger.error("[FirestoreStore] get_severity_feedback failed for %s: %s", doc_id, exc)
            return None

    async def upsert_community_projection(self, projection) -> None:
        """Persist a denormalized community graph snapshot for offline reads."""
        db = self._get_db()
        if not db or not projection:
            return

        community = projection.community
        community_id = str(community.get("id", "")).strip()
        if not community_id:
            return

        now = datetime.now(timezone.utc)
        payload = {
            "community": community,
            "report": projection.event,
            "ngo": projection.ngo,
            "needs": projection.needs,
            "resources": projection.resources,
            "similarity": projection.similarity,
            "coverage_gaps": projection.coverage_gaps,
            "coordination_opportunities": projection.coordination_opportunities,
            "matrix": projection.matrix,
            "provenance": projection.metadata,
            "updated_at": now,
        }

        try:
            await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: db.collection(self._COMMUNITY_PROFILES_COLLECTION).document(community_id).set(payload, merge=True),
            )
        except Exception as exc:
            logger.error("[FirestoreStore] upsert_community_projection failed for %s: %s", community_id, exc)

    async def get_community_projection(self, community_id: str) -> dict | None:
        db = self._get_db()
        if not db or not community_id:
            return None
        try:
            doc = await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: db.collection(self._COMMUNITY_PROFILES_COLLECTION).document(community_id).get(),
            )
            return doc.to_dict() if doc.exists else None
        except Exception as exc:
            logger.error("[FirestoreStore] get_community_projection failed for %s: %s", community_id, exc)
            return None

    async def list_community_projections(self, limit: int = 20) -> list[dict]:
        db = self._get_db()
        if not db:
            return []

        def _stream() -> list[Any]:
            return list(db.collection(self._COMMUNITY_PROFILES_COLLECTION).limit(limit).stream())

        try:
            docs = await asyncio.get_event_loop().run_in_executor(None, _stream)
            return [doc.to_dict() for doc in docs if doc.exists]
        except Exception as exc:
            logger.error("[FirestoreStore] list_community_projections failed: %s", exc)
            return []

    async def upsert_historical_context(
        self,
        event: "UnifiedIngestionEvent",
        severity_payload: dict,
        community_context: dict,
        nearby_volunteer_count: int,
        recommended_tasks: list[dict],
    ) -> None:
        """Stores historical-context snapshot for a resolved community/geohash."""
        db = self._get_db()
        if not db:
            return

        community_id = str(community_context.get("community_id") or "").strip()
        doc_id = community_id or (event.geohash or event.id)
        if not doc_id:
            return

        now = datetime.now(timezone.utc)
        baseline = {
            "historical_crisis_frequency": float(community_context.get("historical_crisis_frequency", 0.0) or 0.0),
            "infrastructure_gaps": community_context.get("infrastructure_gaps", []),
            "vulnerable_groups": community_context.get("vulnerable_groups", []),
        }

        payload = {
            "community_id": community_id,
            "community_name": community_context.get("community_name"),
            "geohash": event.geohash,
            "region": str((event.metadata or {}).get("region") or ""),
            "location": {
                "lat": event.location.latitude,
                "lon": event.location.longitude,
                "admin_level": event.admin_level,
            },
            "latest_event": {
                "event_id": event.id,
                "source": event.source,
                "need_type": event.need_type,
                "severity": event.severity,
                "timestamp": event.timestamp,
                "description": event.description[:500],
            },
            "severity": {
                "acute": float(severity_payload.get("severity_acute", 0.0) or 0.0),
                "chronic": float(severity_payload.get("severity_chronic", 0.0) or 0.0),
                "composite": float(severity_payload.get("composite_urgency", 0.0) or 0.0),
                "classification": severity_payload.get("classification"),
                "recommended_response_time": severity_payload.get("recommended_response_time"),
                "reliability_score": float(severity_payload.get("reliability_score", 0.0) or 0.0),
            },
            "baseline": baseline,
            "nearby_volunteer_count": int(nearby_volunteer_count),
            "recommended_tasks": recommended_tasks,
            "last_updated": now,
        }

        try:
            await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: db.collection(self._COMMUNITY_HISTORY_COLLECTION).document(doc_id).set(payload, merge=True),
            )
        except Exception as exc:
            logger.error("[FirestoreStore] upsert_historical_context failed for %s: %s", doc_id, exc)

    async def upsert_volunteer_area_tasks(
        self,
        event: "UnifiedIngestionEvent",
        community_context: dict,
        severity_payload: dict,
        recommended_tasks: list[dict],
    ) -> None:
        """Stores geospatial volunteer-facing tasks derived from historical context."""
        db = self._get_db()
        if not db:
            return

        if not recommended_tasks:
            return

        community_id = str(community_context.get("community_id") or "").strip()
        now = datetime.now(timezone.utc)
        doc_id = f"{community_id or event.geohash}:{event.id}"

        payload = {
            "task_id": doc_id,
            "community_id": community_id,
            "community_name": community_context.get("community_name"),
            "geohash": event.geohash,
            "lat": event.location.latitude,
            "lon": event.location.longitude,
            "need_type": event.need_type,
            "source": event.source,
            "severity_classification": severity_payload.get("classification"),
            "composite_urgency": float(severity_payload.get("composite_urgency", 0.0) or 0.0),
            "recommended_response_time": severity_payload.get("recommended_response_time"),
            "tasks": recommended_tasks,
            "active": True,
            "created_at": now,
            "updated_at": now,
            "organization_id": (event.metadata or {}).get("organization_id", "GLOBAL"),
            "expires_at": now.replace(microsecond=0),
        }

        # 14-day retention window for volunteer-area tasks.
        payload["expires_at"] = payload["expires_at"] + timedelta(days=14)

        try:
            await asyncio.get_event_loop().run_in_executor(
                None,
                lambda: db.collection(self._VOLUNTEER_TASKS_COLLECTION).document(doc_id).set(payload, merge=True),
            )
        except Exception as exc:
            logger.error("[FirestoreStore] upsert_volunteer_area_tasks failed for %s: %s", doc_id, exc)

    async def list_volunteer_area_tasks(self, limit: int = 100, active_only: bool = True, organization_id: str | None = None) -> list[dict]:
        db = self._get_db()
        if not db:
            return []

        def _stream() -> list[Any]:
            query = db.collection(self._VOLUNTEER_TASKS_COLLECTION)
            if active_only:
                query = query.where("active", "==", True)
            if organization_id:
                query = query.where("organization_id", "==", organization_id)
            
            query = query.order_by("updated_at", direction=self._firestore.Query.DESCENDING).limit(limit)
            return list(query.stream())

        try:
            docs = await asyncio.get_event_loop().run_in_executor(None, _stream)
            return [doc.to_dict() for doc in docs if doc.exists]
        except Exception as exc:
            logger.error("[FirestoreStore] list_volunteer_area_tasks failed: %s", exc)
            return []

    async def list_recent_events(self, limit: int = 50, since: "datetime" | None = None) -> list[dict]:
        """
        Fetch recent ingestion events from multiple sources:
        1. need_regions/{geohash}/events (time-series subcollections)
        2. need_regions top-level docs (most recent region snapshots)
        3. community_historical_context (community-level needs)
        
        Returns events sorted by timestamp (descending), optionally filtered by 'since'.
        Combines all sources and deduplicates by geohash.
        """
        db = self._get_db()
        if not db:
            return []

        def _collect_events() -> list[dict]:
            from datetime import datetime, timezone
            
            events: list[dict] = []
            seen_geohashes = set()
            
            # SOURCE 1: Fetch events from need_regions subcollections
            try:
                regions = list(db.collection(self._COLLECTION).stream())
                
                for region_doc in regions:
                    region_id = region_doc.id
                    region_data = region_doc.to_dict() or {}
                    
                    # Try to fetch from events subcollection first
                    try:
                        events_query = region_doc.reference.collection("events").order_by(
                            "timestamp", direction=self._firestore.Query.DESCENDING
                        ).limit(limit)
                        
                        if since:
                            events_query = events_query.where("timestamp", ">=", since)
                        
                        has_events = False
                        for event_doc in events_query.stream():
                            if event_doc.exists:
                                has_events = True
                                event_data = event_doc.to_dict()
                                event_data["geohash"] = region_id
                                event_data["source_collection"] = "events_subcollection"
                                events.append(event_data)
                                seen_geohashes.add(region_id)
                        
                        # If no events in subcollection but region is recent, use region data
                        if not has_events and since:
                            last_updated = region_data.get("last_updated")
                            if last_updated and isinstance(last_updated, datetime) and last_updated >= since:
                                region_event = {
                                    "geohash": region_id,
                                    "event_id": region_data.get("latest_event_id", f"region_{region_id}"),
                                    "source": region_data.get("latest_event_source", "firestore"),
                                    "need_type": region_data.get("dominant_need", "general_need"),
                                    "severity": region_data.get("max_severity", "moderate"),
                                    "composite_urgency": region_data.get("composite_urgency", 0.0),
                                    "timestamp": last_updated,
                                    "description": region_data.get("latest_text_preview", ""),
                                    "population_affected": region_data.get("event_count", 0),
                                    "centroid_lat": region_data.get("centroid_lat"),
                                    "centroid_lon": region_data.get("centroid_lon"),
                                    "source_collection": "need_regions_toplevel",
                                }
                                events.append(region_event)
                                seen_geohashes.add(region_id)
                    except Exception as e:
                        logger.warning("[FirestoreStore] Error fetching events for region %s: %s", region_id, e)
            except Exception as e:
                logger.warning("[FirestoreStore] Error fetching need_regions: %s", e)
            
            # SOURCE 2: Fetch from community_historical_context collection
            try:
                query = db.collection(self._COMMUNITY_HISTORY_COLLECTION)
                if since:
                    query = query.where("updated_at", ">=", since)
                
                community_docs = list(query.order_by(
                    "updated_at", direction=self._firestore.Query.DESCENDING
                ).limit(limit).stream())
                
                for community_doc in community_docs:
                    if community_doc.exists:
                        community_data = community_doc.to_dict() or {}
                        community_id = community_doc.id
                        
                        # Skip if we already have this geohash
                        if community_id not in seen_geohashes:
                            community_event = {
                                "geohash": community_id,
                                "event_id": f"community_{community_id}",
                                "source": "community_context",
                                "community_id": community_data.get("id"),
                                "community_name": community_data.get("name"),
                                "need_type": community_data.get("primary_need", "general_need"),
                                "severity": community_data.get("severity_level", "moderate"),
                                "composite_urgency": community_data.get("urgency_score", 0.0),
                                "timestamp": community_data.get("updated_at"),
                                "description": community_data.get("description", ""),
                                "latitude": community_data.get("latitude"),
                                "longitude": community_data.get("longitude"),
                                "source_collection": "community_historical_context",
                            }
                            events.append(community_event)
                            seen_geohashes.add(community_id)
            except Exception as e:
                logger.warning("[FirestoreStore] Error fetching community_historical_context: %s", e)
            
            # Sort globally by timestamp descending and return top N
            events.sort(
                key=lambda x: x.get("timestamp") if isinstance(x.get("timestamp"), datetime) else datetime.min,
                reverse=True
            )
            return events[:limit]

        try:
            return await asyncio.get_event_loop().run_in_executor(None, _collect_events)
        except Exception as exc:
            logger.error("[FirestoreStore] list_recent_events failed: %s", exc)
            return []


# Global singleton
firestore_store = FirestoreStore()
