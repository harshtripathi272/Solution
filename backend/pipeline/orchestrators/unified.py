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
from typing import Optional

from pipeline.core.pubsub import broker
from pipeline.core.schemas import UnifiedIngestionEvent, to_crisis_event, FALLBACK_INDIA_LAT, FALLBACK_INDIA_LON
from pipeline.processing.extraction_strategy import extraction_strategy_router
from pipeline.processing.geocoding import geocoding_service
from pipeline.processing.geohash import encode as geohash_encode
from pipeline.processing.aggregation import aggregation_layer
from pipeline.storage import firestore_store, bigquery_store, redis_need_cache
from pipeline.storage.location import location_store
from severity_engine import severity_engine
from severity_engine.constants import CLASSIFICATION_TO_SEVERITY_LABEL

logger = logging.getLogger(__name__)

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
}


def _infer_source_tier(source: str) -> int:
    for prefix, tier in _SOURCE_TIER.items():
        if source.upper().startswith(prefix):
            return tier
    return 2  # default: crowd-sourced


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

        # Step 7 — Storage fan-out (all writes fire concurrently)
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
        storage_tasks = [
            firestore_store.upsert_region(event, final_score),
            firestore_store.append_event(event, final_score),
            firestore_store.upsert_chronic_score(event, severity_payload),
            bigquery_store.append(event, final_score),
            bigquery_store.append_severity_event(event, severity_payload),
            bigquery_store.append_severity_timeseries(event, severity_payload),
        ]
        if event.document_metadata is not None:
            storage_tasks.append(bigquery_store.append_document_event(event, final_score))

        results = await asyncio.gather(
            *storage_tasks,
            return_exceptions=True,   # never let one store failure cancel others
        )
        for idx, result in enumerate(results):
            if isinstance(result, Exception):
                logger.error(
                    "[UnifiedPipeline] Storage task %d failed for %s: %s",
                    idx,
                    event.id,
                    result,
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
