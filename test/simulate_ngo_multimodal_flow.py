import asyncio
import logging
import sys
import os
from datetime import datetime, timezone
from pathlib import Path
from dotenv import load_dotenv

load_dotenv()

# Setup logging
logging.basicConfig(level=logging.INFO, format="%(levelname)s:%(name)s:%(message)s")
logger = logging.getLogger("MultimodalSimulation")

# Add backend to path
sys.path.append(str(Path(__file__).resolve().parents[1] / "backend"))

from pipeline.core.pubsub import broker, TOPIC_INGESTION_NORMALIZED
from pipeline.core.schemas import IngestionLocation, UnifiedIngestionEvent
from pipeline.orchestrators.unified import unified_pipeline
from pipeline.processing.multimodal_preprocessor import multimodal_preprocessor

async def run_multimodal_simulation():
    logger.info("--- Starting NGO Multimodal Form Simulation ---")

    # 1. Start the Unified Pipeline (Storage + Severity)
    # Mocking auth initialization
    import auth as _auth  # noqa: F401
    unified_pipeline.start()

    # 2. Simulate the NGO Worker Report (as would be done in main.py)
    report_description = "Major bridge collapse in Bihar due to monsoon. Flooding visible everywhere. Help needed for 200 people."
    media_urls = [
        "https://example.com/bridge_damage.jpg",
        "https://example.com/flood_video.mp4"
    ]
    
    logger.info("Step 1: Running Multimodal Preprocessing (Gemini Placeholder)...")
    insight = await multimodal_preprocessor.analyze_evidence(
        media_urls=media_urls,
        description_hint=report_description
    )
    
    logger.info(f"AI Insight: {insight.summary}")
    logger.info(f"Destruction Detected: {insight.destruction_detected}, Distress Level: {insight.distress_level}")

    # 3. Create the Normalized Event
    event = UnifiedIngestionEvent(
        id="NGO-SIM-MULTIMODAL-1",
        location=IngestionLocation(latitude=25.5941, longitude=85.1376), # Patna, Bihar
        need_type=insight.detected_needs[0] if insight.detected_needs else "other",
        severity="high",
        timestamp=datetime.now(timezone.utc),
        source="NGO_APP_MOCK_SIM",
        confidence_score=insight.confidence,
        description=f"{report_description}\n\n[Multimodal AI Summary]: {insight.summary}",
        metadata={
            "reporter_uid": "mock-ngo-worker-123",
            "multimodal_analysis": {
                "summary": insight.summary,
                "destruction_detected": insight.destruction_detected,
                "crowd_size_estimate": insight.crowd_size_estimate,
                "distress_level": insight.distress_level,
                "confidence": insight.confidence,
            },
            "media_urls": media_urls,
            "district_population": 2000000,
            "district_area_km2": 3200
        }
    )

    # 4. Inject into the pipeline
    logger.info(f"Step 2: Publishing multimodal event to {TOPIC_INGESTION_NORMALIZED}")
    await broker.publish(TOPIC_INGESTION_NORMALIZED, event)

    # 5. Wait for processing to complete
    logger.info("Waiting for pipeline to process event...")
    await asyncio.sleep(10) # Give it time to hit BigQuery/Firestore mocks
    
    logger.info("--- Multimodal Simulation Cycle Finished ---")
    logger.info("Verifying: Severity score should be boosted by destruction and distress signals.")

if __name__ == "__main__":
    asyncio.run(run_multimodal_simulation())
