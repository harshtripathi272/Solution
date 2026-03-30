"""
Text-only simulation for UnifiedExtractor -> UnifiedPipeline -> Firestore.

This intentionally skips PDF parsing and document stream orchestration.
It validates:
1) LLM extraction works on a single paragraph
2) Event reaches ingestion-normalized
3) need_regions is written in Firestore
"""

from __future__ import annotations

import asyncio
import logging
import os
import sys
import uuid
from datetime import datetime, timezone
from pathlib import Path

from dotenv import load_dotenv

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(levelname)s:%(name)s:%(message)s")
logger = logging.getLogger("TextFlowSimulation")

# Add backend to import path
sys.path.append(str(Path(__file__).resolve().parents[1] / "backend"))

from pipeline.core.pubsub import broker, TOPIC_INGESTION_NORMALIZED
from pipeline.core.schemas import IngestionLocation, UnifiedIngestionEvent
from pipeline.orchestrators.unified import unified_pipeline
from pipeline.processing.geohash import encode as geohash_encode
from pipeline.processing.unified_extractor import nvidia_extractor
from pipeline.storage import firestore_store


async def _wait_for_topic_drain(topic_name: str, timeout_seconds: int = 90) -> bool:
    topic = broker.topics.get(topic_name)
    if not topic or not topic.subscriptions:
        logger.warning("No active subscriptions for topic '%s'", topic_name)
        return False

    async def _join_all() -> None:
        await asyncio.gather(*(sub.queue.join() for sub in topic.subscriptions))

    try:
        await asyncio.wait_for(_join_all(), timeout=timeout_seconds)
        logger.info("Topic '%s' queues drained", topic_name)
        return True
    except asyncio.TimeoutError:
        pending = [sub.queue.qsize() for sub in topic.subscriptions]
        logger.warning("Timeout waiting for '%s'. Pending queue sizes: %s", topic_name, pending)
        return False


async def run() -> None:
    logger.info("--- Starting text-only unified extractor simulation ---")

    # Import auth for firebase_admin initialization side effect
    import auth as _auth  # noqa: F401

    unified_pipeline.start()

    paragraph = (
        "In Rampur district, Uttar Pradesh, several villages reported severe drinking water "
        "shortages this week after hand pumps ran dry. Local health workers observed a rise "
        "in dehydration among children and elderly residents, and requested emergency water "
        "tankers and temporary community filtration units."
    )

    if not os.getenv("NVIDIA_API_KEY"):
        raise RuntimeError("NVIDIA_API_KEY is missing. Set it before running this simulation.")

    extraction = None
    for attempt in range(1, 4):
        extraction = await nvidia_extractor.extract(paragraph)
        if extraction is not None:
            break
        logger.warning("Extractor attempt %d failed (timeout/empty response), retrying...", attempt)
        await asyncio.sleep(2)

    if extraction is None:
        raise RuntimeError("Unified extractor returned None after 3 attempts. Check NVIDIA/API logs.")

    logger.info(
        "Extractor output: need_type=%s severity=%s confidence=%.2f places=%s",
        extraction.need_type,
        extraction.severity,
        extraction.confidence,
        extraction.places,
    )

    # Fixed coordinates to skip geocoding path and make storage deterministic.
    lat, lon = 28.8, 79.0
    run_tag = uuid.uuid4().hex[:8]
    event = UnifiedIngestionEvent(
        id=f"SIM-TEXT-{run_tag}",
        source=f"SIM_NGO_TEXT_{run_tag}",
        timestamp=datetime.now(timezone.utc),
        location=IngestionLocation(latitude=lat, longitude=lon),
        need_type=extraction.need_type or "other",
        severity=extraction.severity or "moderate",
        confidence_score=max(0.0, min(extraction.confidence, 1.0)),
        description=paragraph,
        metadata={
            "source_org": "Simulation",
            "ingest_channel": "text_unified_extractor_test",
            "places": extraction.places,
            "raw_extraction": extraction.raw_json,
            "region": "rampur",
        },
        needs_geocoding=False,
    )

    expected_geohash = geohash_encode(lat, lon, precision=5)
    logger.info(
        "Dedup identity for this run: source=%s geohash=%s need_type=%s date=%s",
        event.source,
        expected_geohash,
        event.need_type,
        event.timestamp.strftime("%Y-%m-%d"),
    )

    logger.info("Publishing simulated event %s to %s", event.id, TOPIC_INGESTION_NORMALIZED)
    await broker.publish(TOPIC_INGESTION_NORMALIZED, event)

    await _wait_for_topic_drain(TOPIC_INGESTION_NORMALIZED, timeout_seconds=120)

    region_doc = await firestore_store.get_region(expected_geohash)
    if not region_doc:
        raise RuntimeError(
            f"No Firestore need_regions document found for geohash={expected_geohash}."
        )

    logger.info("Firestore write confirmed for geohash=%s", expected_geohash)
    logger.info(
        "Region snapshot: dominant_need=%s latest_event_id=%s event_count=%s",
        region_doc.get("dominant_need"),
        region_doc.get("latest_event_id"),
        region_doc.get("event_count"),
    )

    logger.info("--- Text-only simulation completed successfully ---")


if __name__ == "__main__":
    asyncio.run(run())
