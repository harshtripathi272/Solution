import asyncio
import argparse
import logging
import os
import sys
import time

# Ensure the backend directory is in the import path
backend_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from pipeline.core.pubsub import broker
from pipeline.orchestrators.unified import unified_pipeline
from pipeline.ingestors.manager import ingestion_manager
import dotenv

logger = logging.getLogger("build_historical_context")

async def main():
    dotenv.load_dotenv()
    logging.basicConfig(level=logging.INFO, force=True)
    parser = argparse.ArgumentParser(description="One-time historical context builder.")
    parser.add_argument("--max-reports", type=int, default=120, help="Max NGO reports to scrape once")
    parser.add_argument("--wait-seconds", type=int, default=300, help="Seconds to wait for async pipeline fan-out")
    args = parser.parse_args()
    logger.info("Initializing Historical Context & Community Graph Projection...")

    # 1. Start the unified pipeline (listens for "ingestion-normalized" events)
    unified_pipeline.start()
    
    # 2. Run the real spider-backed NGO ingestion once.
    logger.info("Running one-time NGO spider scrape (max_reports=%d)...", args.max_reports)
    start_time = time.time()
    count = await ingestion_manager.ingest_ngo_reports_once(max_reports=args.max_reports)
    scrape_time = time.time() - start_time
    logger.info("Scraping completed in %.2f seconds. Published %d normalized NGO events into the unified pipeline.", scrape_time, count)

    logger.info("Waiting for the pipeline to finish processing all %d tasks (%ds timeout)...", count, args.wait_seconds)
    start_wait = time.time()
    for elapsed in range(0, args.wait_seconds, 10):
        await asyncio.sleep(10)
        current_elapsed = time.time() - start_wait
        logger.info("Still processing... elapsed %.2f seconds", current_elapsed)
    
    total_time = time.time() - start_time
    logger.info("✅ Historical context build process completed in %.2f seconds! Data should be available in Firestore & Neo4j.", total_time)

if __name__ == "__main__":
    asyncio.run(main())
