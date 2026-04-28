"""
pipeline/core/pubsub.py
-----------------------
Pub/Sub abstraction layer for the SevaSetu crisis pipeline.

Two modes controlled by the PUBSUB_USE_REAL environment variable:

  PUBSUB_USE_REAL=false  (default)
      Uses the original in-process asyncio-queue broker.
      No GCP credentials needed. Good for local dev / unit tests.

  PUBSUB_USE_REAL=true
      Uses Google Cloud Pub/Sub (Project B: analytics project).
      Requires:
        - PUBSUB_PROJECT_ID        = your-project-b-id
        - GCP_ANALYTICS_CREDENTIALS_PATH = /path/to/analytics_pubsub_key.json
      Publish calls are non-blocking (gRPC Future).
      Subscribe calls start a background streaming-pull thread managed by the
      GCP library — automatically reconnects on transient failures.

Public API (same in both modes):
    await broker.publish(topic_name, message_object)
    broker.subscribe(topic_name, subscription_suffix, async_callback)
    await broker.shutdown()

Topic / Subscription naming convention (Project B):
    logical name            GCP Topic                             GCP Subscription(s)
    ─────────────────────── ───────────────────────────────────   ─────────────────────────────────────────────
    ingestion-normalized    sevasetu-ingestion-normalized         sevasetu-ingestion-normalized-unified
    official-alerts         sevasetu-official-alerts              sevasetu-official-alerts-validation
                                                                  sevasetu-official-alerts-allocation
    citizen-reports         sevasetu-citizen-reports              sevasetu-citizen-reports-validation
                                                                  sevasetu-citizen-reports-allocation
    social-media-raw        sevasetu-social-media-raw             sevasetu-social-media-raw-validation
    verified-crisis         sevasetu-verified-crisis              sevasetu-verified-crisis-allocation
    document-intelligence   sevasetu-document-intelligence-raw    (reserved — no subscriber yet)
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
from typing import Any, Callable, Dict, List, Optional

logger = logging.getLogger(__name__)


# Topic constants — shared across the whole application
TOPIC_INGESTION_NORMALIZED      = "ingestion-normalized"
TOPIC_OFFICIAL_ALERTS           = "official-alerts"
TOPIC_CITIZEN_REPORTS           = "citizen-reports"
TOPIC_SOCIAL_MEDIA_RAW          = "social-media-raw"
TOPIC_VERIFIED_CRISIS           = "verified-crisis"
TOPIC_DOCUMENT_INTELLIGENCE_RAW = "document-intelligence-raw"

# Mapping: logical topic name → GCP topic ID (Project B)
_TOPIC_ID_MAP: Dict[str, str] = {
    TOPIC_INGESTION_NORMALIZED:      "sevasetu-ingestion-normalized",
    TOPIC_OFFICIAL_ALERTS:           "sevasetu-official-alerts",
    TOPIC_CITIZEN_REPORTS:           "sevasetu-citizen-reports",
    TOPIC_SOCIAL_MEDIA_RAW:          "sevasetu-social-media-raw",
    TOPIC_VERIFIED_CRISIS:           "sevasetu-verified-crisis",
    TOPIC_DOCUMENT_INTELLIGENCE_RAW: "sevasetu-document-intelligence-raw",
}

# Mapping: logical topic name → GCP subscription ID suffix → subscription ID (Project B)
# subscription_suffix is the sub_name passed by the caller (e.g. "unified-pipeline-processor")
_SUBSCRIPTION_MAP: Dict[str, Dict[str, str]] = {
    TOPIC_INGESTION_NORMALIZED: {
        "unified-pipeline-processor": "sevasetu-ingestion-normalized-unified",
    },
    TOPIC_OFFICIAL_ALERTS: {
        "validation-cache-updater": "sevasetu-official-alerts-validation",
        "volunteer-allocator":      "sevasetu-official-alerts-allocation",
    },
    TOPIC_CITIZEN_REPORTS: {
        "validation-checker": "sevasetu-citizen-reports-validation",
        "volunteer-allocator": "sevasetu-citizen-reports-allocation",
    },
    TOPIC_SOCIAL_MEDIA_RAW: {
        "validation-checker": "sevasetu-social-media-raw-validation",
    },
    TOPIC_VERIFIED_CRISIS: {
        "volunteer-allocator-v": "sevasetu-verified-crisis-allocation",
    },
}


# ─────────────────────────────────────────────────────────────────────────────
# Helper — JSON serialiser that handles dataclasses / Pydantic models / datetimes
# ─────────────────────────────────────────────────────────────────────────────
def _serialise(obj: Any) -> bytes:
    """Convert a Pydantic model (or any JSON-serialisable object) to bytes."""
    if hasattr(obj, "model_dump"):          # Pydantic v2
        payload = obj.model_dump(mode="json")
    elif hasattr(obj, "dict"):               # Pydantic v1
        payload = obj.dict()
    else:
        payload = obj
    return json.dumps(payload, default=str).encode("utf-8")


def _deserialise(data: bytes, model_class: Any = None) -> Any:
    """Decode bytes back to a dict or Pydantic model."""
    payload = json.loads(data.decode("utf-8"))
    if model_class is not None:
        return model_class(**payload)
    return payload


# ─────────────────────────────────────────────────────────────────────────────
# Mock broker — original in-process implementation (kept as fallback)
# ─────────────────────────────────────────────────────────────────────────────
class _MockSubscription:
    def __init__(self, name: str, callback: Callable[[Any], Any]):
        self.name = name
        self.callback = callback
        self.queue: asyncio.Queue = asyncio.Queue()
        self._task = None

    async def _worker(self):
        logger.info(f"[MockPubSub] Subscriber {self.name} listening...")
        semaphore = asyncio.Semaphore(10)

        async def _run(msg):
            async with semaphore:
                try:
                    await self.callback(msg)
                except Exception as e:
                    logger.error(f"[MockPubSub] Error in {self.name} callback: {e}")
                finally:
                    self.queue.task_done()

        while True:
            try:
                msg = await self.queue.get()
                if msg is None:
                    break
                asyncio.create_task(_run(msg))
            except Exception as e:
                logger.error(f"[MockPubSub] Error in {self.name} loop: {e}")

    def start(self):
        self._task = asyncio.create_task(self._worker())

    async def stop(self):
        await self.queue.put(None)
        if self._task:
            await self._task


class _MockTopic:
    def __init__(self, name: str):
        self.name = name
        self.subscriptions: List[_MockSubscription] = []

    def add_subscription(self, sub: _MockSubscription):
        self.subscriptions.append(sub)
        sub.start()

    async def publish(self, message: Any):
        event_id = getattr(message, "id", "unknown")
        tier = getattr(message, "tier", "n/a")
        logger.info(f"[MockPubSub] [{self.name}] Publishing Event: {event_id} | Tier: {tier}")
        for sub in self.subscriptions:
            await sub.queue.put(message)


class _MockBroker:
    """Original in-process asyncio-queue broker. Used when PUBSUB_USE_REAL=false."""

    def __init__(self):
        self.topics: Dict[str, _MockTopic] = {}
        for t in _TOPIC_ID_MAP.keys():
            self.topics[t] = _MockTopic(t)

    def subscribe(self, topic_name: str, sub_name: str, callback: Callable) -> _MockSubscription:
        if topic_name not in self.topics:
            self.topics[topic_name] = _MockTopic(topic_name)
        sub = _MockSubscription(sub_name, callback)
        self.topics[topic_name].add_subscription(sub)
        return sub

    async def publish(self, topic_name: str, message: Any):
        if topic_name not in self.topics:
            self.topics[topic_name] = _MockTopic(topic_name)
        await self.topics[topic_name].publish(message)

    async def shutdown(self):
        logger.info("[MockPubSub] Shutting down...")


# ─────────────────────────────────────────────────────────────────────────────
# Real GCP Pub/Sub broker
# ─────────────────────────────────────────────────────────────────────────────
class _GCPPubSubBroker:
    """
    Google Cloud Pub/Sub broker for Project B (analytics project).

    Publish: serialise event → PublisherClient.publish() [non-blocking].
    Subscribe: start a streaming-pull thread via SubscriberClient.subscribe().
               Received messages are dispatched to the registered async callback
               via asyncio.run_coroutine_threadsafe() so they execute in the
               main event loop.
    """

    def __init__(self, project_id: str, credentials_path: Optional[str]):
        try:
            from google.cloud import pubsub_v1
            from google.oauth2 import service_account
        except ImportError:
            raise RuntimeError(
                "google-cloud-pubsub is not installed. "
                "Run: pip install google-cloud-pubsub==2.21.4"
            )

        self._project_id = project_id
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._futures: List[Any] = []          # streaming-pull Future handles

        # Build credentials (explicit JSON key for Project B)
        if credentials_path:
            _creds = service_account.Credentials.from_service_account_file(
                credentials_path,
                scopes=["https://www.googleapis.com/auth/cloud-platform"],
            )
            self._publisher = pubsub_v1.PublisherClient(credentials=_creds)
            self._subscriber = pubsub_v1.SubscriberClient(credentials=_creds)
        else:
            # Fall back to Application Default Credentials
            logger.warning(
                "[GCPPubSub] GCP_ANALYTICS_CREDENTIALS_PATH not set — using ADC."
            )
            self._publisher = pubsub_v1.PublisherClient()
            self._subscriber = pubsub_v1.SubscriberClient()

        logger.info(
            "[GCPPubSub] Initialised for project '%s' with explicit credentials=%s",
            project_id,
            bool(credentials_path),
        )

    def _topic_path(self, logical_name: str) -> str:
        gcp_topic = _TOPIC_ID_MAP.get(logical_name, f"sevasetu-{logical_name}")
        return self._publisher.topic_path(self._project_id, gcp_topic)

    def _subscription_path(self, logical_topic: str, sub_name: str) -> str:
        subs = _SUBSCRIPTION_MAP.get(logical_topic, {})
        gcp_sub_id = subs.get(sub_name, f"sevasetu-{logical_topic}-{sub_name}")
        return self._subscriber.subscription_path(self._project_id, gcp_sub_id)

    def subscribe(self, topic_name: str, sub_name: str, callback: Callable) -> None:
        """
        Start a streaming-pull subscription. The callback is async and will be
        scheduled on the main event loop for every received message.
        """
        # Capture the event loop at subscribe time (called from lifespan startup)
        self._loop = asyncio.get_event_loop()

        sub_path = self._subscription_path(topic_name, sub_name)
        logger.info("[GCPPubSub] Starting streaming pull: %s", sub_path)

        def _sync_callback(message):
            try:
                payload = json.loads(message.data.decode("utf-8"))
                # Reconstruct the correct schema object if possible
                msg_obj = _reconstruct(topic_name, payload)
                if self._loop and not self._loop.is_closed():
                    asyncio.run_coroutine_threadsafe(callback(msg_obj), self._loop)
                message.ack()
            except Exception as exc:
                logger.error(
                    "[GCPPubSub] Callback error on %s: %s — nacking.", sub_path, exc
                )
                message.nack()

        future = self._subscriber.subscribe(sub_path, callback=_sync_callback)
        self._futures.append(future)
        logger.info("[GCPPubSub] Subscribed → %s", sub_path)

    async def publish(self, topic_name: str, message: Any) -> None:
        """Serialize and publish a message to GCP. Non-blocking (fire-and-forget future)."""
        topic_path = self._topic_path(topic_name)
        data = _serialise(message)
        try:
            future = self._publisher.publish(topic_path, data)
            # Schedule result check without blocking the event loop
            asyncio.get_event_loop().run_in_executor(None, future.result)
            logger.debug("[GCPPubSub] Published to %s (%d bytes)", topic_path, len(data))
        except Exception as exc:
            logger.error("[GCPPubSub] Publish failed for %s: %s", topic_name, exc)

    async def shutdown(self) -> None:
        """Cancel all streaming-pull futures gracefully."""
        logger.info("[GCPPubSub] Shutting down %d subscriber(s)...", len(self._futures))
        for fut in self._futures:
            fut.cancel()
        self._subscriber.close()
        logger.info("[GCPPubSub] All subscribers cancelled.")


def _reconstruct(topic_name: str, payload: dict) -> Any:
    """
    Best-effort reconstruction of the event schema object from a raw dict.
    Falls back to the raw dict if the schema class is unavailable.
    """
    try:
        if topic_name == TOPIC_INGESTION_NORMALIZED:
            from pipeline.core.schemas import UnifiedIngestionEvent
            return UnifiedIngestionEvent(**payload)
        else:
            from pipeline.core.schemas import CrisisEvent
            return CrisisEvent(**payload)
    except Exception:
        return payload


# ─────────────────────────────────────────────────────────────────────────────
# Factory — returns the correct broker based on PUBSUB_USE_REAL env var
# ─────────────────────────────────────────────────────────────────────────────
def _build_broker():
    use_real = os.getenv("PUBSUB_USE_REAL", "false").strip().lower()
    if use_real != "true":
        logger.info(
            "[PubSub] PUBSUB_USE_REAL=false → using in-process mock broker. "
            "Set PUBSUB_USE_REAL=true + credentials to enable real GCP Pub/Sub."
        )
        return _MockBroker()

    project_id = os.getenv("PUBSUB_PROJECT_ID", "").strip()
    if not project_id:
        logger.error(
            "[PubSub] PUBSUB_USE_REAL=true but PUBSUB_PROJECT_ID is not set — "
            "falling back to mock broker."
        )
        return _MockBroker()

    cred_path = os.getenv("GCP_ANALYTICS_CREDENTIALS_PATH", "").strip() or None
    try:
        return _GCPPubSubBroker(project_id=project_id, credentials_path=cred_path)
    except Exception as exc:
        logger.error(
            "[PubSub] Failed to initialise GCP broker (%s) — falling back to mock.", exc
        )
        return _MockBroker()


# ─────────────────────────────────────────────────────────────────────────────
# Global singleton — imported by all pipeline modules
# ─────────────────────────────────────────────────────────────────────────────
broker = _build_broker()
