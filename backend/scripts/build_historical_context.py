import asyncio
import logging
import os
import sys

# Ensure the backend directory is in the import path
backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from pipeline.core.pubsub import broker
from pipeline.orchestrators.unified import unified_pipeline
from pipeline.ingestors.global_rss_monitor import GlobalRSSMonitor
from pipeline.ingestors.ngo_reports import NGOReportsIngestor
import dotenv

logger = logging.getLogger("build_historical_context")

async def main():
    dotenv.load_dotenv()
    logging.basicConfig(level=logging.INFO)
    logger.info("Initializing Historical Context & Community Graph Projection...")

    # 1. Start the unified pipeline (listens for "ingestion-normalized" events)
    unified_pipeline.start()
    
    # 2. Init specific spiders (fetching high-volume context events)
    spiders = [
        GlobalRSSMonitor(interval_seconds=10, max_articles=80),
        NGOReportsIngestor(interval_seconds=10, max_reports=30)
    ]
    
    all_events = []
    for spider in spiders:
        logger.info(f"Running spider: {spider.name}")
        try:
            events = await spider.fetch_events()
            logger.info(f"{spider.name} yielded {len(events)} events.")
            all_events.extend(events)
        except Exception as e:
            logger.error(f"Error running {spider.name}: {e}")

    logger.info(f"Publishing {len(all_events)} events to the unified pipeline...")
    
    # 3. Push events through the UnifiedPipeline. 
    # This automatically invokes community_graph_service.project_event -> Neo4j & Firestore
    for event in all_events:
        await broker.publish("ingestion-normalized", event)
        
    logger.info("Waiting for the pipeline to finish processing all tasks (15s)...")
    await asyncio.sleep(15)
    
    logger.info("✅ Historical context built successfully! Data is available in Firestore & Neo4j.")

if __name__ == "__main__":
    asyncio.run(main())
