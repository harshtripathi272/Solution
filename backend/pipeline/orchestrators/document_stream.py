from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any

from pipeline.core.pubsub import TOPIC_DOCUMENT_INTELLIGENCE_RAW, TOPIC_INGESTION_NORMALIZED, broker
from pipeline.core.schemas import DocumentMetadata, IngestionLocation, NeedTemporality, UnifiedIngestionEvent
from pipeline.processing.document_extractor import DocumentDownloadError, document_extractor
from pipeline.processing.ner import document_ner_adapter
from pipeline.storage import firestore_store

logger = logging.getLogger(__name__)


class DocumentStreamOrchestrator:
    """Processes raw document URLs and emits normalized events into main ingestion stream."""

    def start(self) -> None:
        broker.subscribe(
            TOPIC_DOCUMENT_INTELLIGENCE_RAW,
            "document-stream-processor",
            self._process,
        )
        logger.info("[DocumentStream] Subscribed to '%s'", TOPIC_DOCUMENT_INTELLIGENCE_RAW)

    async def _process(self, payload: dict[str, Any]) -> None:
        pdf_url = str((payload or {}).get("pdf_url", "")).strip()
        source_org = str((payload or {}).get("source_org", "NGO")).strip() or "NGO"
        published_on = str((payload or {}).get("published_on", "")).strip()
        snippet = str((payload or {}).get("snippet", "")).strip()

        if not pdf_url:
            logger.warning("[DocumentStream] Ignoring payload without pdf_url")
            return

        try:
            extraction = await document_extractor.extract_from_pdf_url(
                pdf_url=pdf_url,
                source_org=source_org,
                publication_date_hint=published_on,
                text_hint=snippet,
            )
            if extraction is None:
                logger.warning("[DocumentStream] Extraction returned no result for %s", pdf_url)
                return

            if await firestore_store.is_document_hash_processed(extraction.document_sha256):
                # Already seen content hash; keep recency info updated without duplicate ingestion.
                await firestore_store.upsert_document_registry(
                    metadata=DocumentMetadata(
                        source_ngo=source_org,
                        pdf_url=pdf_url,
                        publication_date=extraction.publication_date,
                        sha256_hash=extraction.document_sha256,
                    ),
                    status="processed",
                    extraction_version=1,
                )
                logger.info("[DocumentStream] Skipping already-processed hash for %s", pdf_url)
                return

            event = self._to_unified_event(
                source_org=source_org,
                pdf_url=pdf_url,
                published_on=published_on,
                snippet=snippet,
                extraction=extraction,
            )

            await firestore_store.upsert_document_registry(
                metadata=event.document_metadata,
                status="processed",
                extraction_version=1,
            )

            await broker.publish(TOPIC_INGESTION_NORMALIZED, event)
            logger.info("[DocumentStream] Published document event %s to ingestion-normalized", event.id)

        except DocumentDownloadError as exc:
            status = exc.status_code or 0
            if status in {403, 404}:
                await firestore_store.upsert_document_registry(
                    metadata=DocumentMetadata(
                        source_ngo=source_org,
                        pdf_url=pdf_url,
                        publication_date=None,
                        sha256_hash=f"unreachable:{pdf_url}",
                    ),
                    status="unreachable",
                    failure_reason=str(exc),
                    extraction_version=1,
                )
            logger.error("[DocumentStream] Download failed for %s: %s", pdf_url, exc)
        except Exception as exc:
            logger.error("[DocumentStream] Processing failed for %s: %s", pdf_url, exc)

    @staticmethod
    def _to_unified_event(source_org: str, pdf_url: str, published_on: str, snippet: str, extraction) -> UnifiedIngestionEvent:
        ts = extraction.publication_date or datetime.now(timezone.utc)
        adapter_result = document_ner_adapter.adapt(extraction.raw_json)
        need_type = adapter_result.need_type
        severity = adapter_result.severity

        # Start at India centroid until standard geocoding stage resolves extracted places.
        location = IngestionLocation(latitude=20.5937, longitude=78.9629)

        stable_seed = f"{source_org}|{pdf_url}|{extraction.document_sha256[:16]}"
        import hashlib
        event_id = f"DOC-{hashlib.sha256(stable_seed.encode('utf-8')).hexdigest()[:24]}"

        metadata = {
            "source_org": source_org,
            "pdf_url": pdf_url,
            "published_on": published_on,
            "snippet": snippet[:400],
            "source_excerpt": extraction.source_excerpt,
            "places": adapter_result.places or extraction.places,
            "recommended_interventions": extraction.interventions,
            "vulnerable_groups": extraction.vulnerable_groups,
            "infrastructure_gaps": extraction.infrastructure_gaps,
            "seasonal_urgency": extraction.seasonal_urgency,
            "region": extraction.places[-1] if extraction.places else "india",
            "ingest_channel": "document_intelligence_stream",
            "source_type": "ngo_report",
            "lineage": "document",
            "raw_extraction": extraction.raw_json,
        }

        return UnifiedIngestionEvent(
            id=event_id,
            location=location,
            need_type=need_type,
            severity=severity,
            timestamp=ts,
            source=f"DOC_{source_org.upper().replace(' ', '_')}",
            need_temporality=adapter_result.need_temporality,
            confidence_score=max(0.0, min(adapter_result.confidence, 1.0)),
            description=(extraction.source_excerpt or snippet or f"{source_org} report")[:500],
            metadata=metadata,
            population_affected=max(0, extraction.population_affected),
            source_tier=2,
            needs_geocoding=True,
            document_metadata=DocumentMetadata(
                source_ngo=source_org,
                pdf_url=pdf_url,
                publication_date=extraction.publication_date,
                sha256_hash=extraction.document_sha256,
            ),
        )


document_stream_orchestrator = DocumentStreamOrchestrator()
