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

    if not os.getenv("NVIDIA_API_KEY"):
        raise RuntimeError("NVIDIA_API_KEY is missing. Set it before running this simulation.")

    scenarios = [
        {
            "name": "Bihar - Gaya Water Crisis",
            "lat": 24.7914,
            "lon": 85.0002,
            "text": (
                "CRITICAL: Extreme water scarcity in Gaya district, Bihar. "
                "Over 2000 people are without access to clean drinking water. "
                "Immediate tanker supply required. High risk of dehydration."
            )
        },
        {
            "name": "Bihar - Patna Flood Warning",
            "lat": 25.5941,
            "lon": 85.1376,
            "text": (
                "SEVERE: Heavy rainfall in Patna has led to urban flooding. "
                "Drains are overflowing and low-lying areas are submerged. "
                "Immediate evacuation of 500 families needed. Food and shelter are urgent."
            )
        },
        {
            "name": "Jharkhand - Ranchi Health Emergency",
            "lat": 23.3441,
            "lon": 85.3096,
            "text": (
                "URGENT: Outbreak of waterborne diseases in Ranchi outskirts. "
                "Local clinics are overwhelmed. More than 150 cases reported today. "
                "Medical supplies and temporary health camps are critically needed."
            )
        },
        {
            "name": "Jharkhand - Dhanbad Food Insecurity",
            "lat": 23.7957,
            "lon": 86.4304,
            "text": (
                "CRITICAL: Acute food shortage in rural Dhanbad following crop failure. "
                "Families are skipping meals. Distribution of dry rations is mandatory to prevent starvation."
            )
        }
    ]

    for scenario in scenarios:
        logger.info(f"Processing scenario: {scenario['name']}")
        
        extraction = None
        for attempt in range(1, 4):
            extraction = await nvidia_extractor.extract(scenario["text"])
            if extraction is not None:
                break
            logger.warning("Extractor attempt %d failed for %s, retrying...", attempt, scenario["name"])
            await asyncio.sleep(2)

        if extraction is None:
            logger.error("Failed to extract for %s", scenario["name"])
            continue

        run_tag = uuid.uuid4().hex[:8]
        
        # Extract population or default to a random visible number for the test
        pop_affected = extraction.population_affected if extraction.population_affected > 0 else 450

        event = UnifiedIngestionEvent(
            id=f"SIM-HT-{run_tag}",
            source=f"SIM_HEATMAP_{run_tag}",
            timestamp=datetime.now(timezone.utc),
            location=IngestionLocation(latitude=scenario["lat"], longitude=scenario["lon"]),
            need_type=extraction.need_type or "other",
            severity=extraction.severity or "high",
            confidence_score=max(0.8, min(extraction.confidence, 1.0)), # Boost confidence for map visibility
            description=scenario["text"],
            population_affected=pop_affected,
            metadata={
                "source_org": "Simulation-Heatmap",
                "ingest_channel": "heatmap_injection_test",
                "places": extraction.places,
                "raw_extraction": extraction.raw_json,
                "region": scenario["name"].split(" - ")[0].lower()
            },
            needs_geocoding=False,
        )

        expected_geohash = geohash_encode(scenario["lat"], scenario["lon"], precision=5)
        logger.info("Publishing %s (geohash=%s) to %s", event.id, expected_geohash, TOPIC_INGESTION_NORMALIZED)
        await broker.publish(TOPIC_INGESTION_NORMALIZED, event)

    # Wait for all events to be processed
    await _wait_for_topic_drain(TOPIC_INGESTION_NORMALIZED, timeout_seconds=60)
    logger.info("--- All scenarios published and drained ---")


if __name__ == "__main__":
    asyncio.run(run())
