"""
NER (Named Entity Recognition) extraction — UNIFIED with PDF document extraction.

Backward compatibility layer for text-based extraction.
Now delegates to pipeline.processing.unified_extractor.GeminiExtractor.

Extracts structured location, need_type, and severity from free-text
field reports, news articles, or KoboToolbox survey responses.

Called ONLY when an event has `needs_geocoding=True` — i.e., the
ingestor could not resolve a real lat/lon and fell back to the India
centroid. This is the primary case for news articles and text surveys.

Gracefully returns None when:
    • NVIDIA_API_KEY is not set in the environment
    • The provider response cannot be parsed as valid JSON
    • The openai package is not installed
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field
from typing import List, Optional

from pipeline.core.schemas import NeedTemporality
from pipeline.processing.unified_extractor import (
    GeminiExtractor,
    UnifiedExtractionResult,
    gemini_extractor,
)

logger = logging.getLogger(__name__)


# Backward compat: thin wrappers around UnifiedExtractionResult
@dataclass
class NERResult:
    """
    Backward compat wrapper for text extraction results.
    Subset of UnifiedExtractionResult (text-only fields).
    """
    places: List[str] = field(default_factory=list)
    need_type: Optional[str] = None
    severity: Optional[str] = None
    confidence: float = 0.5


# Backward compat: adapter class for document results to unified schema
@dataclass
class DocumentNERAdapterResult:
    """Backward compat wrapper for document extraction results."""
    places: List[str] = field(default_factory=list)
    need_type: str = "other"
    severity: str = "moderate"
    confidence: float = 0.5
    need_temporality: NeedTemporality = NeedTemporality.CHRONIC


# Backward compat wrapper: NERExtractor delegates to unified extractor
class NERExtractor:
    """
    Backward compat wrapper for text-based NER extraction.
    
    Now just delegates to pipeline.processing.unified_extractor.GeminiExtractor.
    Use gemini_extractor.extract(text) directly for new code.
    """

    def __init__(self) -> None:
        # Delegate to singleton from unified_extractor
        self._extractor = gemini_extractor
        self._enabled = self._extractor._enabled

    def _init_client(self) -> None:
        # Delegate initialization status to unified extractor
        pass

    async def extract(self, text: str) -> Optional[NERResult]:
        """
        Extract location entities and crisis metadata from raw text.
        
        Delegates to unified extractor. Returns NERResult (backward compat).
        Returns None when NER is disabled or parsing fails.
        """
        if not self._enabled or not text:
            return None

        # Call unified extractor
        unified_result = await self._extractor.extract(text)
        if not unified_result:
            return None

        # Convert UnifiedExtractionResult → NERResult (backward compat)
        return NERResult(
            places=unified_result.places,
            need_type=unified_result.need_type if unified_result.need_type != "other" else None,
            severity=unified_result.severity if unified_result.severity != "moderate" else None,
            confidence=unified_result.confidence,
        )


class DocumentNERAdapter:
    """
    Maps document-extracted entities to unified schema format.
    
    Now just wraps UnifiedExtractionResult, for backward compat with
    code expecting DocumentNERAdapterResult naming.
    """

    def adapt(self, payload: dict) -> DocumentNERAdapterResult:
        """
        Adapt a document extraction payload to DocumentNERAdapterResult.
        
        This is a thin compat layer — in new code, use UnifiedExtractionResult directly.
        """
        # Extract fields same way UnifiedExtractionResult does
        places = self._normalize_list(payload.get("places")) or self._normalize_list(payload.get("locations"))
        need_type = self._normalize_need_type(str(payload.get("need_type", "other")))
        severity = self._normalize_severity(
            raw_label=str(payload.get("severity", "")),
            raw_score=payload.get("severity_score"),
        )
        confidence = self._safe_float(payload.get("confidence"), default=0.5)
        confidence = max(0.0, min(confidence, 1.0))

        return DocumentNERAdapterResult(
            places=[str(p).strip() for p in places if str(p).strip()],
            need_type=need_type,
            severity=severity,
            confidence=confidence,
            need_temporality=NeedTemporality.CHRONIC,
        )

    @staticmethod
    def _normalize_need_type(value: str) -> str:
        """Delegate to unified extractor normalization."""
        return GeminiExtractor._normalize_need_type(value)

    @staticmethod
    def _normalize_severity(raw_label: str, raw_score) -> str:
        """Delegate to unified extractor normalization."""
        return GeminiExtractor._normalize_severity(raw_label, raw_score)

    @staticmethod
    def _normalize_list(value) -> List[str]:
        """Delegate to unified extractor normalization."""
        return GeminiExtractor._normalize_list(value)

    @staticmethod
    def _safe_float(value, default: float = 0.0) -> float:
        """Delegate to unified extractor normalization."""
        return GeminiExtractor._safe_float(value, default)


# Global singletons (backward compat)
ner_extractor = NERExtractor()
document_ner_adapter = DocumentNERAdapter()

