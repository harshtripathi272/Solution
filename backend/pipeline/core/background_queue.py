"""
Background task queue for non-critical pipeline operations.

Allows user-facing requests (e.g., login) to complete immediately without waiting
for heavy pipeline processing. Critical path operations complete first, deferred
operations happen asynchronously in the background.
"""

import asyncio
import logging
from typing import Callable, Any, Optional
from enum import Enum

logger = logging.getLogger(__name__)


class TaskPriority(Enum):
    """Task execution priority levels."""
    CRITICAL = 0      # User-facing operations (should never queue)
    HIGH = 1          # Storage that blocks query results
    NORMAL = 2        # Analytics/metrics (default)
    LOW = 3           # Reporting/cleanup


class BackgroundTask:
    """Represents a background task."""
    
    def __init__(
        self,
        func: Callable,
        priority: TaskPriority = TaskPriority.NORMAL,
        name: str = "",
    ):
        self.func = func
        self.priority = priority
        self.name = name or getattr(func, '__name__', 'unknown')
    
    async def execute(self) -> None:
        """Execute the task, logging errors but not raising."""
        try:
            if asyncio.iscoroutinefunction(self.func):
                await self.func()
            else:
                self.func()
            logger.debug(f"[BGQueue] Task {self.name} completed")
        except Exception as e:
            logger.error(f"[BGQueue] Task {self.name} failed: {e}")


class BackgroundQueue:
    """
    Async background task queue with priority support.
    
    Non-critical operations (analytics, detailed logging, etc.) are deferred
    to execute after critical path operations complete. This prevents expensive
    pipeline operations from blocking user-facing API requests.
    """
    
    def __init__(self, max_concurrent: int = 5):
        self._queue: asyncio.PriorityQueue[tuple[int, int, BackgroundTask]] = asyncio.PriorityQueue()
        self._worker_task: Optional[asyncio.Task] = None
        self._max_concurrent = max_concurrent
        self._active_tasks = 0
        self._total_processed = 0
        self._semaphore = asyncio.Semaphore(max_concurrent)
        self._running = False
        self._counter = 0  # Counter to break priority ties without comparing tasks
    
    async def start(self) -> None:
        """Start the background worker."""
        if self._running:
            return
        
        self._running = True
        self._worker_task = asyncio.create_task(self._worker_loop())
        logger.info(f"[BGQueue] Started with max_concurrent={self._max_concurrent}")
    
    async def stop(self) -> None:
        """Stop the worker and wait for pending tasks."""
        if not self._running:
            return
        
        self._running = False
        
        # Allow existing tasks to finish
        if self._worker_task:
            try:
                # Give worker a chance to finish current batch
                await asyncio.wait_for(self._worker_task, timeout=5.0)
            except asyncio.TimeoutError:
                logger.warning("[BGQueue] Worker timeout during shutdown, cancelling")
                self._worker_task.cancel()
        
        logger.info(f"[BGQueue] Stopped. Processed {self._total_processed} tasks")
    
    async def _worker_loop(self) -> None:
        """Main worker loop that processes queued tasks."""
        logger.info("[BGQueue] Worker started")
        
        while self._running:
            try:
                # Get task with timeout to allow clean shutdown
                try:
                    _, _, task = await asyncio.wait_for(
                        self._queue.get(),
                        timeout=1.0
                    )
                except asyncio.TimeoutError:
                    continue
                
                # Execute with concurrency limit
                async with self._semaphore:
                    self._active_tasks += 1
                    try:
                        await task.execute()
                    finally:
                        self._active_tasks -= 1
                        self._total_processed += 1
                        
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"[BGQueue] Worker error: {e}")
    
    async def submit(
        self,
        func: Callable,
        priority: TaskPriority = TaskPriority.NORMAL,
        name: str = "",
    ) -> None:
        """
        Submit a task for background execution.
        
        Non-awaitable - returns immediately after queuing.
        """
        if not self._running:
            logger.warning(f"[BGQueue] Queue not running, executing {name or func.__name__} immediately")
            try:
                if asyncio.iscoroutinefunction(func):
                    await func()
                else:
                    func()
            except Exception as e:
                logger.error(f"[BGQueue] Immediate execution failed: {e}")
            return
        
        task = BackgroundTask(func, priority, name)
        
        # Lower enum value = higher priority
        # Use counter to break ties so we don't compare BackgroundTask objects
        self._counter += 1
        await self._queue.put((priority.value, self._counter, task))
        logger.debug(f"[BGQueue] Queued {name or func.__name__} (priority={priority.name})")
    
    def get_stats(self) -> dict[str, Any]:
        """Get queue statistics."""
        return {
            "running": self._running,
            "queue_size": self._queue.qsize(),
            "active_tasks": self._active_tasks,
            "total_processed": self._total_processed,
            "max_concurrent": self._max_concurrent,
        }


# Global singleton
_queue: Optional[BackgroundQueue] = None


def get_background_queue() -> BackgroundQueue:
    """Get or create the global background queue."""
    global _queue
    if _queue is None:
        _queue = BackgroundQueue(max_concurrent=10)
    return _queue


async def submit_background_task(
    func: Callable,
    priority: TaskPriority = TaskPriority.NORMAL,
    name: str = "",
) -> None:
    """
    Convenience function to submit a task to the background queue.
    
    Example:
        async def log_metrics():
            # Heavy processing that doesn't block user requests
            pass
        
        await submit_background_task(log_metrics, TaskPriority.LOW, "metrics")
    """
    queue = get_background_queue()
    await queue.submit(func, priority, name)
