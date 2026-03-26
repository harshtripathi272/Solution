import asyncio
import logging
from typing import Callable, Dict, List, Any
from .schemas import CrisisEvent

logger = logging.getLogger(__name__)

class Subscription:
    def __init__(self, name: str, callback: Callable[[CrisisEvent], Any]):
        self.name = name
        self.callback = callback
        self.queue: asyncio.Queue = asyncio.Queue()
        self._task = None

    async def _worker(self):
        logger.info(f"Subscriber {self.name} listening...")
        while True:
            try:
                msg = await self.queue.get()
                if msg is None:  # Shutdown signal
                    break
                await self.callback(msg)
                self.queue.task_done()
            except Exception as e:
                logger.error(f"Error in subscriber {self.name}: {str(e)}")

    def start(self):
        self._task = asyncio.create_task(self._worker())

    async def stop(self):
        await self.queue.put(None)
        if self._task:
            await self._task

class Topic:
    def __init__(self, name: str):
        self.name = name
        self.subscriptions: List[Subscription] = []

    def add_subscription(self, sub: Subscription):
        self.subscriptions.append(sub)
        sub.start()

    async def publish(self, message: CrisisEvent):
        logger.info(f"[Topic: {self.name}] Publishing Event: {message.id} | Tier: {message.tier}")
        for sub in self.subscriptions:
            await sub.queue.put(message)

class PubSubBroker:
    def __init__(self):
        self.topics: Dict[str, Topic] = {}

    def create_topic(self, topic_name: str) -> Topic:
        if topic_name not in self.topics:
            self.topics[topic_name] = Topic(topic_name)
        return self.topics[topic_name]

    def subscribe(self, topic_name: str, sub_name: str, callback: Callable) -> Subscription:
        topic = self.create_topic(topic_name)
        sub = Subscription(sub_name, callback)
        topic.add_subscription(sub)
        return sub

    async def publish(self, topic_name: str, message: CrisisEvent):
        topic = self.create_topic(topic_name)
        await topic.publish(message)

# Global singleton broker for the application
broker = PubSubBroker()
