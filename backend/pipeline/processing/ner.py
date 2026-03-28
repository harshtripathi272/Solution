"""
NER (Named Entity Recognition) extractor using Google Gemini Flash.

Extracts structured location, need_type, and severity from free-text
field reports, news articles, or KoboToolbox survey responses.

Called ONLY when an event has `needs_geocoding=True` — i.e., the
ingestor could not resolve a real lat/lon and fell back to the India
centroid. This is the primary case for news articles and text surveys.

Gracefully returns None when:
  • GEMINI_API_KEY is not set in the environment
  • The Gemini response cannot be parsed as valid JSON
  • The google-generativeai package is not installed
"""

from __future__ import annotations

import json
import logging
import os
import re
from dataclasses import dataclass, field
from typing import List, Optional

logger = logging.getLogger(__name__)

# Optional dependency guard
try:
    import google.generativeai as genai  # type: ignore
    _GENAI_AVAILABLE = True
except ImportError:
    _GENAI_AVAILABLE = False


# Result data class
@dataclass
class NERResult:
    """Structured extraction output from Gemini Flash."""
    # Ordered list of place names from most to least specific
    # e.g. ["Gopalganj", "Bihar"] or ["Patna district", "Bihar"]
    places: List[str] = field(default_factory=list)
    # Refined need_type extracted from context (may upgrade the ingestor guess)
    need_type: Optional[str] = None
    # Refined severity extracted from context
    severity: Optional[str] = None
    # Confidence in the extraction (0.0–1.0)
    confidence: float = 0.5


# Prompt template
_NER_PROMPT = """\
You are a humanitarian data extraction assistant. Analyse the following text
from a news article or field report about a crisis or community need in India.

Extract ONLY the following and reply with a single JSON object — no prose, no
markdown fences:

{{
  "places": ["<most specific place>", "<district>", "<state>"],
  "need_type": "<one of: flood | cyclone | earthquake | medical | fire | violence | food | education | other>",
  "severity": "<one of: critical | high | moderate | low>",
  "confidence": <float between 0.0 and 1.0 reflecting your certainty>
}}

Rules:
• "places" must be real Indian place names; use as many levels as found.
• If only a state is mentioned, put just the state name.
• If no Indian location can be found, return "places": [].
• Do not invent place names.

Text:
\"\"\"
{text}
\"\"\"
"""


# Extractor class
class NERExtractor:
    """Singleton NER service backed by Gemini Flash."""

    _MODEL_NAME = "gemini-1.5-flash"
    _MAX_TEXT_LEN = 1500   # truncate long articles to keep latency low

    def __init__(self) -> None:
        self._model = None
        self._enabled = False
        self._init_client()

    def _init_client(self) -> None:
        api_key = os.environ.get("GEMINI_API_KEY", "").strip()
        if not api_key:
            logger.info("[NER] GEMINI_API_KEY not set — NER extraction disabled.")
            return
        if not _GENAI_AVAILABLE:
            logger.warning("[NER] google-generativeai not installed — NER disabled.")
            return
        try:
            genai.configure(api_key=api_key)
            self._model = genai.GenerativeModel(self._MODEL_NAME)
            self._enabled = True
            logger.info("[NER] Gemini Flash NER extractor ready.")
        except Exception as exc:
            logger.error("[NER] Failed to initialise Gemini client: %s", exc)

    # Public API
    async def extract(self, text: str) -> Optional[NERResult]:
        """
        Extract location entities and crisis metadata from raw text.

        Returns None when NER is disabled or parsing fails.
        """
        if not self._enabled or not text:
            return None

        truncated = text[: self._MAX_TEXT_LEN]
        prompt = _NER_PROMPT.format(text=truncated)

        try:
            response = await self._model.generate_content_async(prompt)
            raw = response.text or ""
            return self._parse(raw)
        except Exception as exc:
            logger.warning("[NER] Gemini call failed: %s", exc)
            return None

    # Helpers
    @staticmethod
    def _parse(raw: str) -> Optional[NERResult]:
        """Parse JSON out of the Gemini response (strips any markdown fences)."""
        # Strip markdown code fences if present
        cleaned = re.sub(r"```(?:json)?", "", raw).strip("` \n")
        try:
            data = json.loads(cleaned)
        except json.JSONDecodeError:
            # Attempt to extract the first JSON object via regex
            match = re.search(r"\{.*\}", cleaned, re.DOTALL)
            if not match:
                logger.warning("[NER] Could not parse JSON from Gemini response.")
                return None
            try:
                data = json.loads(match.group())
            except json.JSONDecodeError:
                logger.warning("[NER] Regex-extracted JSON still invalid.")
                return None

        places = data.get("places") or []
        if isinstance(places, str):
            places = [places]

        return NERResult(
            places=places,
            need_type=data.get("need_type"),
            severity=data.get("severity"),
            confidence=float(data.get("confidence", 0.5)),
        )


# Global singleton
ner_extractor = NERExtractor()
