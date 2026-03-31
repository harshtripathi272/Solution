"""
Simulation script to verify the E2E Document Intelligence -> Unified Pipeline flow.
This script bypasses Scrapy and pushes a synthetic NGO report directly into the stream.
"""

import asyncio
import logging
import sys
import os
from dotenv import load_dotenv
load_dotenv()
from pathlib import Path

# Setup logging to see the pipeline in action
logging.basicConfig(level=logging.INFO, format="%(levelname)s:%(name)s:%(message)s")
logger = logging.getLogger("Simulation")

# Add backend to path
sys.path.append(str(Path(__file__).resolve().parents[1] / "backend"))

from pipeline.core.pubsub import broker, TOPIC_DOCUMENT_INTELLIGENCE_RAW
from pipeline.orchestrators.document_stream import document_stream_orchestrator
from pipeline.orchestrators.unified import unified_pipeline


async def _wait_for_topic_drain(topic_name: str, timeout_seconds: int = 180) -> bool:
    """Wait until all subscriber queues for a topic are drained."""
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
        logger.warning(
            "Timeout waiting for topic '%s' to drain. Pending queue sizes: %s",
            topic_name,
            pending,
        )
        return False

async def run_simulation():
    logger.info("--- Starting SevaSetu Pipeline E2E Simulation ---")

    # 1. Initialize Firebase and Orchestrators
    import auth as _auth  # noqa: F401  # Import side effect initializes firebase_admin
    
    document_stream_orchestrator.start()
    unified_pipeline.start()

    # 2. Synthetic NGO Report Payload
    # Using a known tiny 1-page PDF for maximum speed
    synthetic_report = {
        "source_org": "Sphere India",
        "pdf_url": "https://www.actionaidindia.org/wp-content/uploads/2025/07/Information-Asymmetry-and-Digital-Divide-During-the-Pandemic-I-Report-I-Final.pdf", # Known small sitrep
        "published_on": "2024-03-30",
        "snippet": "Public parks in Delhi"
    }

    logger.info(f"Step 1: Publishing synthetic report to {TOPIC_DOCUMENT_INTELLIGENCE_RAW}")
    await broker.publish(TOPIC_DOCUMENT_INTELLIGENCE_RAW, synthetic_report)

    # 3. Wait for async queue pipeline to finish instead of fixed sleep
    logger.info("Waiting for document topic queue to drain...")
    await _wait_for_topic_drain(TOPIC_DOCUMENT_INTELLIGENCE_RAW, timeout_seconds=240)

    logger.info("Waiting for unified ingestion queue to drain...")
    await _wait_for_topic_drain("ingestion-normalized", timeout_seconds=240)
    
    logger.info("--- Simulation Cycle Finished ---")
    logger.info("Check logs for '[FirestoreStore] Upserted need_regions/...' confirmations.")

if __name__ == "__main__":
    if not os.getenv("NVIDIA_API_KEY"):
        print("ERROR: NVIDIA_API_KEY not found in environment!")
        sys.exit(1)
        
    asyncio.run(run_simulation())
