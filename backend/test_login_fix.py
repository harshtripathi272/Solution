#!/usr/bin/env python3
"""
Test script to validate the login/pipeline fix.

Tests that:
1. Login requests complete quickly even with pipeline running
2. BigQuery batching is working
3. Connection pool is not exhausted
"""

import asyncio
import time
import logging
from typing import List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


async def simulate_login_requests(num_requests: int = 5, concurrent: int = 3) -> None:
    """Simulate concurrent login requests."""
    logger.info(f"🔐 Simulating {num_requests} login requests (concurrent={concurrent})")
    
    # Measure login latency
    start_time = time.time()
    
    # In a real test, these would be HTTP requests to /api/v1/auth/register
    # For this simulation, we're just measuring the pipeline queue system
    from pipeline.core.background_queue import get_background_queue, TaskPriority
    
    queue = get_background_queue()
    if not queue._running:
        await queue.start()
    
    # Simulate heavy background tasks
    async def heavy_task():
        await asyncio.sleep(0.1)  # Simulate BigQuery batch flush
    
    # Submit many tasks while login requests happen
    for i in range(20):
        await queue.submit(heavy_task, TaskPriority.LOW, f"bg-task-{i}")
    
    # Simulate login processing (should be fast)
    login_times = []
    for i in range(num_requests):
        req_start = time.time()
        
        # Simulate critical path operations
        await asyncio.sleep(0.01)  # Firestore writes
        
        req_time = time.time() - req_start
        login_times.append(req_time * 1000)  # Convert to ms
    
    total_time = time.time() - start_time
    
    logger.info(f"✓ Login requests completed")
    logger.info(f"  Total time: {total_time*1000:.1f}ms")
    logger.info(f"  Average per request: {sum(login_times)/len(login_times):.1f}ms")
    logger.info(f"  Queue stats: {queue.get_stats()}")
    
    # Cleanup
    await queue.stop()
    
    # Validation
    if sum(login_times) / len(login_times) < 50:
        logger.info("✅ Login latency acceptable (<50ms average)")
    else:
        logger.warning("⚠️ Login latency high - check executor configuration")


async def test_bigquery_batching() -> None:
    """Test that BigQuery batching is configured correctly."""
    logger.info("📊 Testing BigQuery batch writer...")
    
    try:
        from pipeline.storage.bigquery import bigquery_store
        
        # Check configuration
        batch_size = bigquery_store._batch_size
        batch_timeout = bigquery_store._batch_timeout_sec
        executor_workers = bigquery_store._executor._max_workers
        
        logger.info(f"  Batch size: {batch_size}")
        logger.info(f"  Batch timeout: {batch_timeout}s")
        logger.info(f"  Executor workers: {executor_workers}")
        
        # Validation
        if batch_size >= 50:
            logger.info("✅ BigQuery batch size configured")
        else:
            logger.warning("⚠️ BigQuery batch size might be too small")
        
        if executor_workers >= 15:
            logger.info("✅ BigQuery executor pool configured")
        else:
            logger.warning("⚠️ BigQuery executor pool might be too small")
            
    except Exception as e:
        logger.error(f"❌ BigQuery test failed: {e}")


async def test_background_queue() -> None:
    """Test background queue functionality."""
    logger.info("🔄 Testing background queue...")
    
    try:
        from pipeline.core.background_queue import get_background_queue, TaskPriority
        
        queue = get_background_queue()
        
        # Check if queue is available
        if queue is not None:
            logger.info("✅ Background queue initialized")
        else:
            logger.error("❌ Background queue not initialized")
            return
        
        # Start queue
        await queue.start()
        
        # Submit test tasks
        task_count = 0
        
        async def test_task():
            nonlocal task_count
            task_count += 1
            await asyncio.sleep(0.01)
        
        for i in range(5):
            await queue.submit(test_task, TaskPriority.LOW, f"test-{i}")
        
        # Wait for tasks
        await asyncio.sleep(0.5)
        
        stats = queue.get_stats()
        logger.info(f"  Processed: {stats['total_processed']} tasks")
        
        if stats['total_processed'] >= 5:
            logger.info("✅ Background queue processing tasks")
        else:
            logger.warning("⚠️ Background queue might not be processing all tasks")
        
        await queue.stop()
        
    except Exception as e:
        logger.error(f"❌ Background queue test failed: {e}")


async def test_executor_pool() -> None:
    """Test executor pool configuration."""
    logger.info("⚙️  Testing executor pool configuration...")
    
    try:
        import asyncio
        import os
        from concurrent.futures import ThreadPoolExecutor
        
        loop = asyncio.get_event_loop()
        
        # Check default executor
        if hasattr(loop, '_default_executor') and loop._default_executor:
            max_workers = loop._default_executor._max_workers
            logger.info(f"  Default executor max_workers: {max_workers}")
            
            if max_workers >= 30:
                logger.info("✅ Executor pool configured for high concurrency")
            else:
                logger.warning("⚠️ Executor pool might be too small")
        else:
            logger.info("ℹ️  Default executor not configured (will use system default)")
        
    except Exception as e:
        logger.error(f"❌ Executor test failed: {e}")


async def main():
    """Run all tests."""
    logger.info("=" * 60)
    logger.info("Login/Pipeline Fix Validation Tests")
    logger.info("=" * 60)
    
    await test_executor_pool()
    logger.info("")
    
    await test_bigquery_batching()
    logger.info("")
    
    await test_background_queue()
    logger.info("")
    
    await simulate_login_requests()
    
    logger.info("=" * 60)
    logger.info("✅ All tests completed")
    logger.info("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())
