from __future__ import annotations

import json
import logging
from pathlib import Path

import httpx

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

            payload = self._parse_jsonl_line(raw, line_no)
            if payload is None:
                continue

            await broker.publish(TOPIC_DOCUMENT_INTELLIGENCE_RAW, payload)
            published += 1

        logger.info("[DocumentIngestionService] published %d document raw messages", published)
        return published

    async def ingest_jsonl_url(self, jsonl_url: str, max_documents: int | None = None) -> int:
        if not jsonl_url:
            raise ValueError("jsonl_url is required")

        published = 0
        line_no = 0
        timeout = httpx.Timeout(60.0, connect=10.0)
        async with httpx.AsyncClient(timeout=timeout, follow_redirects=True) as client:
            async with client.stream("GET", jsonl_url) as response:
                response.raise_for_status()
                async for raw_line in response.aiter_lines():
                    line_no += 1
                    if max_documents is not None and published >= max_documents:
                        break

                    payload = self._parse_jsonl_line(raw_line, line_no)
                    if payload is None:
                        continue

                    await broker.publish(TOPIC_DOCUMENT_INTELLIGENCE_RAW, payload)
                    published += 1

        logger.info("[DocumentIngestionService] published %d document raw messages", published)
        return published

    @staticmethod
    def _parse_jsonl_line(raw: str, line_no: int) -> dict | None:
        line = (raw or "").strip().lstrip("\ufeff")
        if not line:
            return None

        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            logger.warning("[DocumentIngestionService] skipping invalid JSON line %d", line_no)
            return None

        pdf_url = str(item.get("pdf_url", "")).strip()
        if not pdf_url:
            return None

        source_org = str(item.get("source_org", "NGO")).strip() or "NGO"
        return {
            "pdf_url": pdf_url,
            "source_org": source_org,
            "published_on": item.get("published_on"),
            "source_url": item.get("source_url"),
            "snippet": item.get("snippet") or item.get("raw_text") or "",
        }


document_ingestion_service = DocumentIngestionService()
