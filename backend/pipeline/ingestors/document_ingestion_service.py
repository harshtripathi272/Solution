from __future__ import annotations

import json
import logging
from pathlib import Path

from pipeline.core.pubsub import TOPIC_DOCUMENT_INTELLIGENCE_RAW, broker

logger = logging.getLogger(__name__)


class DocumentIngestionService:
    """Companion ingestion service for NGO document JSONL output."""

    async def ingest_jsonl(self, file_path: str, max_documents: int | None = None) -> int:
        path = Path(file_path)
        if not path.exists():
            raise FileNotFoundError(f"JSONL file not found: {file_path}")

        published = 0
        for line_no, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
            if max_documents is not None and published >= max_documents:
                break

            line = raw.strip().lstrip("\ufeff")
            if not line:
                continue

            try:
                item = json.loads(line)
            except json.JSONDecodeError:
                logger.warning("[DocumentIngestionService] skipping invalid JSON line %d", line_no)
                continue

            pdf_url = str(item.get("pdf_url", "")).strip()
            if not pdf_url:
                continue

            source_org = str(item.get("source_org", "NGO")).strip() or "NGO"
            payload = {
                "pdf_url": pdf_url,
                "source_org": source_org,
                "published_on": item.get("published_on"),
                "source_url": item.get("source_url"),
                "snippet": item.get("snippet") or item.get("raw_text") or "",
            }

            await broker.publish(TOPIC_DOCUMENT_INTELLIGENCE_RAW, payload)
            published += 1

        logger.info("[DocumentIngestionService] published %d document raw messages", published)
        return published


document_ingestion_service = DocumentIngestionService()
