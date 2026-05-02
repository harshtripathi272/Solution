"""
Unified Pipeline Orchestrator — the central data processing spine.

Subscribes to the `ingestion-normalized` pub/sub topic (populated by all
ingestors via PeriodicIngestor.publish_events). For every event it runs:

  1. NER extraction    — only when event.needs_geocoding is True
  2. Geocoding         — resolve NER places → (lat, lon, admin_level)
  3. Geohash encoding  — (lat, lon) → 5-char geohash region key
  4. Schema finalization — set source_tier, upgrade need_type/severity from NER
  5. Aggregation       — dedup check + weighted score merge
  6. Storage fan-out   — Firestore (dual-write) + BigQuery + Redis need cache

The existing `allocation_engine` and `validation_service` maintain their own
independent subscriptions to `official-alerts`, `citizen-reports`, etc.
This pipeline is additive and does NOT modify those flows.

Threading model
---------------
All stages are async. Blocking calls (googlemaps, Firestore SDK, BigQuery)
are wrapped in asyncio.get_event_loop().run_in_executor() inside each module.
"""

from __future__ import annotations

import logging
from typing import Any, Optional

from pipeline.core.pubsub import broker
from pipeline.core.schemas import UnifiedIngestionEvent, to_crisis_event, FALLBACK_INDIA_LAT, FALLBACK_INDIA_LON
from pipeline.core.background_queue import submit_background_task, TaskPriority
from pipeline.processing.extraction_strategy import extraction_strategy_router
from pipeline.processing.community_graph import community_graph_service
from pipeline.processing.geocoding import geocoding_service
from pipeline.processing.geohash import encode as geohash_encode
from pipeline.processing.aggregation import aggregation_layer
from pipeline.storage import firestore_store, bigquery_store, redis_need_cache
from pipeline.storage.location import location_store
from severity_engine import severity_engine
from severity_engine.constants import CLASSIFICATION_TO_SEVERITY_LABEL

logger = logging.getLogger(__name__)

_TASK_TEMPLATES: dict[str, list[dict[str, Any]]] = {
    "medical": [
        {"title": "Support anganwadi nutrition screening", "skills": ["medical", "counseling"]},
        {"title": "Assist maternal and child health outreach", "skills": ["medical"]},
    ],
    "food": [
        {"title": "Coordinate ration verification and distribution", "skills": ["logistics"]},
        {"title": "Map high-risk households for follow-up", "skills": ["counseling"]},
    ],
    "flood": [
        {"title": "Run safe-water and sanitation check", "skills": ["rescue", "logistics"]},
        {"title": "Prioritize vulnerable households for evacuation", "skills": ["rescue"]},
    ],
    "other": [
        {"title": "Conduct rapid household vulnerability survey", "skills": ["logistics", "counseling"]},
    ],
}

# Source tier mapping by ingestor name prefix
_SOURCE_TIER: dict[str, int] = {
    "GDACS":      1,
    "NDMA":       1,
    "OPENWEATHER":1,
    "NEWS_API":   3,
    "NEWSDATA_IO":3,
    "SURVEY":     2,
    "KOBO":       2,
    "USHAHIDI":   2,
    "ACLED":      2,
    "GLOBAL_RSS": 3,  # Deep-scraped free news, contextual tier
    "MASTODON":   2,  # Social media, crowd-sourced tier
    "PIB_RSS":    1,  # Official public information bulletins
    "IMD_ALERTS": 1,  # Official meteorological alerts
    "RELIEFWEB":  1,  # Humanitarian alert source
}


def _infer_source_tier(source: str) -> int:
    for prefix, tier in _SOURCE_TIER.items():
        if source.upper().startswith(prefix):
            return tier
    return 2  # default: crowd-sourced


def _build_historical_tasks(
    event: UnifiedIngestionEvent,
    severity_payload: dict[str, Any],
    community_context: dict[str, Any],
    nearby_volunteer_count: int,
) -> list[dict[str, Any]]:
    templates = _TASK_TEMPLATES.get(event.need_type, _TASK_TEMPLATES["other"])
    urgency = float(severity_payload.get("composite_urgency", 0.0) or 0.0)
    recurrence = float(community_context.get("historical_crisis_frequency", 0.0) or 0.0)
    infra_gaps = community_context.get("infrastructure_gaps", []) or []
    vulnerable = community_context.get("vulnerable_groups", []) or []

    tasks: list[dict[str, Any]] = []
    for idx, template in enumerate(templates, start=1):
        gap_penalty = 0.15 if nearby_volunteer_count < 3 else 0.0
        priority = max(0.0, min(1.0, urgency + (0.02 * min(recurrence, 10.0)) + gap_penalty))
        tasks.append(
            {
                "task_code": f"{event.need_type}:{idx}",
                "title": template["title"],
                "required_skills": template.get("skills", []),
                "priority": round(priority, 3),
                "recommended_response_time": severity_payload.get("recommended_response_time", "48h"),
                "historical_drivers": {
                    "infrastructure_gaps": infra_gaps,
                    "vulnerable_groups": vulnerable,
                    "historical_crisis_frequency": round(recurrence, 3),
                },
                "volunteer_gap": max(0, 3 - nearby_volunteer_count),
            }
        )
    return tasks


class UnifiedPipeline:
    """
    Single-subscriber orchestrator for the data unification pipeline.
    """

    def start(self) -> None:
        broker.subscribe(
            "ingestion-normalized",
            "unified-pipeline-processor",
            self._process,
        )
        logger.info("[UnifiedPipeline] Subscribed to 'ingestion-normalized' ✓")

    # ------------------------------------------------------------------
    # Main processing handler
    # ------------------------------------------------------------------
    async def _process(self, event: UnifiedIngestionEvent) -> None:
        logger.info("[UnifiedPipeline] Processing event %s from %s", event.id, event.source)

        # Step 1 — Intelligent Extraction Strategy (pattern matching → NER as fallback)
        # This router decides per-ingestor whether to:
        #   - Skip entirely (GDACS/NDMA have all data)
        #   - Use fast pattern matching (cheap, handles 80% of cases)
        #   - Fall back to NVIDIA NER (expensive, for ambiguous/unstructured text)
        ner_places: list[str] = []

        if event.needs_geocoding:
            extraction_result = await extraction_strategy_router.extract_with_strategy(event)
            
            if extraction_result:
                # Apply extracted need_type/severity if more confident
                if extraction_result.get("need_type") and \
                   extraction_result.get("confidence_score", 0.5) >= event.confidence_score:
                    event = event.model_copy(update={"need_type": extraction_result["need_type"]})
                
                if extraction_result.get("severity") and \
                   extraction_result.get("confidence_score", 0.5) >= event.confidence_score:
                    event = event.model_copy(update={"severity": extraction_result["severity"]})
                
                # Extract places for geocoding
                ner_places = extraction_result.get("places") or []
                
                logger.info(
                    "[UnifiedPipeline] Extracted %s/%s (places=%d) for %s via strategy",
                    extraction_result.get("need_type"),
                    extraction_result.get("severity"),
                    len(ner_places),
                    event.id,
                )
            else:
                logger.debug(
                    "[UnifiedPipeline] No extraction result for %s (pattern/NER skipped)",
                    event.id
                )

        # Step 2 — Geocoding
        geo_result = None
        if event.needs_geocoding and ner_places:
            geo_result = await geocoding_service.geocode(ner_places)
            if geo_result:
                from pipeline.core.schemas import IngestionLocation
                event = event.model_copy(update={
                    "location":   IngestionLocation(
                        latitude=geo_result.lat,
                        longitude=geo_result.lon,
                    ),
                    "admin_level":  geo_result.admin_level,
                    "confidence_score": min(
                        event.confidence_score * geo_result.confidence + 0.1, 1.0
                    ),
                    "needs_geocoding": False,  # resolved — clear flag
                })
                # Persist resolved location in metadata for debugging
                event = event.model_copy(update={
                    "metadata": {
                        **event.metadata,
                        "resolved_address": geo_result.resolved_name,
                        "geocode_confidence": round(geo_result.confidence, 2),
                    }
                })
                logger.info(
                    "[UnifiedPipeline] Geocoded event %s → %s (admin=%s)",
                    event.id, geo_result.resolved_name, geo_result.admin_level,
                )

        # Step 3 — Geohash encoding
        if not event.geohash:
            gh = geohash_encode(event.location.latitude, event.location.longitude, precision=5)
            event = event.model_copy(update={"geohash": gh})

        # Step 4 — Source tier annotation
        tier = _infer_source_tier(event.source)
        event = event.model_copy(update={"source_tier": tier})

        community_context = community_graph_service.resolve_community(event)
        if community_context:
            event = event.model_copy(
                update={
                    "metadata": {
                        **event.metadata,
                        **community_context,
                    },
                }
            )

        # Step 5 — Aggregation (dedup + score merge)
        is_duplicate, merged_score = aggregation_layer.process(
            event_id=event.id,
            source=event.source,
            geohash=event.geohash,
            need_type=event.need_type,
            timestamp=event.timestamp,
            severity=event.severity,
            confidence=event.confidence_score,
        )

        if is_duplicate:
            logger.debug("[UnifiedPipeline] Skipped duplicate: %s", event.id)
            return

        # Step 6 — Multi-dimensional severity scoring (acute/chronic/composite)
        nearby = location_store.get_nearby(
            crisis_lat=event.location.latitude,
            crisis_lon=event.location.longitude,
            radius_km=20.0,
        )

        # Inject latest ground-truth feedback (if present) before score calculation.
        feedback = await firestore_store.get_severity_feedback(event.geohash, event.need_type)
        if feedback:
            event = event.model_copy(
                update={
                    "metadata": {
                        **event.metadata,
                        "ground_truth_feedback": feedback,
                    },
                }
            )

        severity_result = await severity_engine.calculate(
            event,
            nearby_volunteer_count=len(nearby),
        )

        severity_payload = severity_result.to_dict()
        severity_payload["legacy_merged_score"] = merged_score

        classification = severity_payload.get("classification", "Moderate")
        severity_label = CLASSIFICATION_TO_SEVERITY_LABEL.get(classification, event.severity)
        final_score = float(severity_payload.get("composite_urgency", merged_score))

        event = event.model_copy(
            update={
                "severity": severity_label,
                "metadata": {
                    **event.metadata,
                    "severity_engine": severity_payload,
                },
            }
        )

        community_context = {
            "community_id": str(event.metadata.get("community_id", "")),
            "community_name": str(event.metadata.get("community_name", "")),
            "historical_crisis_frequency": float(event.metadata.get("historical_crisis_frequency", 0.0) or 0.0),
            "infrastructure_gaps": event.metadata.get("infrastructure_gaps", []) or [],
            "vulnerable_groups": event.metadata.get("vulnerable_groups", []) or [],
        }
        recommended_tasks = _build_historical_tasks(
            event=event,
            severity_payload=severity_payload,
            community_context=community_context,
            nearby_volunteer_count=len(nearby),
        )

        # Step 7 — Storage fan-out (critical-path sync, analytics deferred)
        if not event.geohash:
            logger.warning(
                "[UnifiedPipeline] No geohash for event %s — skipping storage.", event.id
            )
            return

        logger.info(
            "[UnifiedPipeline] Storing event %s | geohash=%s | need=%s | score=%.3f | tier=%d",
            event.id, event.geohash, event.need_type, final_score, event.source_tier,
        )

        import asyncio
        
        # CRITICAL PATH: Must complete before event is considered "stored"
        # These operations are needed for:
        # - Real-time query results
        # - Task allocation
        # - Region aggregation
        critical_tasks = [
            firestore_store.upsert_region(event, final_score),
            firestore_store.append_event(event, final_score),
            firestore_store.upsert_chronic_score(event, severity_payload),
            bigquery_store.append(event, final_score),  # Queued, non-blocking
        ]
        
        # NORMAL PRIORITY: Analytics and context enrichment
        # These improve query results but aren't strictly required
        normal_tasks = [
            firestore_store.upsert_historical_context(
                event,
                severity_payload,
                community_context,
                len(nearby),
                recommended_tasks,
            ),
            firestore_store.upsert_volunteer_area_tasks(
                event,
                community_context,
                severity_payload,
                recommended_tasks,
            ),
            bigquery_store.append_severity_event(event, severity_payload),  # Queued
        ]
        
        # LOW PRIORITY: Deferred analytics and reporting
        # These can happen in the background without blocking user operations
        async def deferred_operations():
            try:
                # Graph analytics and timeseries can be deferred
                await bigquery_store.append_severity_timeseries(event, severity_payload)  # Queued
                await community_graph_service.project_event(event, severity_payload)
                
                if event.document_metadata is not None:
                    await bigquery_store.append_document_event(event, final_score)  # Queued
            except Exception as e:
                logger.error(f"[UnifiedPipeline] Deferred operations failed for {event.id}: {e}")
        
        # Execute critical path first
        results = await asyncio.gather(
            *critical_tasks,
            return_exceptions=True,
        )
        
        # Check for critical failures
        critical_failures = [r for r in results if isinstance(r, Exception)]
        if critical_failures:
            logger.error(
                "[UnifiedPipeline] Critical storage failed for %s: %s",
                event.id,
                critical_failures[0],
            )
            await firestore_store.create_pipeline_alert(
                event_id=event.id,
                stage="critical_storage",
                message="Critical storage operation failed",
                details={"exception": str(critical_failures[0])},
                severity="error",
            )
            return  # Don't continue if critical path fails
        
        # Execute normal-priority operations
        results = await asyncio.gather(
            *normal_tasks,
            return_exceptions=True,
        )
        
        for idx, result in enumerate(results):
            if isinstance(result, Exception):
                logger.error(
                    "[UnifiedPipeline] Storage task %d failed for %s: %s",
                    idx,
                    event.id,
                    result,
                )

        # Submit deferred operations to background queue (non-blocking)
        await submit_background_task(
            deferred_operations,
            TaskPriority.LOW,
            f"deferred-{event.id}",
        )

        logger.info("[UnifiedPipeline] Storage fan-out completed for %s", event.id)

        # Redis cache is synchronous-friendly, call after gather
        redis_need_cache.set(event.geohash, event.need_type, final_score)
        redis_need_cache.set_composite(event.geohash, final_score)

        # Step 8 — Downstream Publishing (for Allocation/Validation)
        # We re-publish the ENRICHED event to its tier-based topic so that
        # downstream services (AllocationEngine) can work with geocoded/geohashed data.
        if event.source_tier == 1:
            downstream_topic = "official-alerts"
        elif event.source_tier == 2:
            downstream_topic = "citizen-reports"
        else:
            downstream_topic = "social-media-raw"

        crisis_event = to_crisis_event(
            event,
            tier=event.source_tier,
            verified=(event.source_tier == 1),
        )

        await broker.publish(downstream_topic, crisis_event)
        logger.info("[UnifiedPipeline] Re-published enriched event %s to %s", event.id, downstream_topic)

        logger.info("[UnifiedPipeline] Done — event %s stored and re-published.", event.id)


# Global singleton — started in main.py lifespan
unified_pipeline = UnifiedPipeline()
