import logging
from typing import Any, Dict, List, Optional
from dataclasses import dataclass
import os

logger = logging.getLogger(__name__)

@dataclass
class MultimodalInsight:
    summary: str
    destruction_detected: bool
    crowd_size_estimate: int
    distress_level: float  # 0.0 to 1.0
    detected_needs: List[str]
    confidence: float
    population_affected: int = 0

class MultimodalPreprocessor:
    """
    Preprocessing layer to extract humanitarian signals from non-text media
    using multimodal AI (e.g., Gemini).
    """

    def __init__(self):
        self.api_key = os.getenv("GEMINI_API_KEY", "PLACEHOLDER")
        self.enabled = self.api_key != "PLACEHOLDER"
        if not self.enabled:
            logger.warning("[Multimodal] GEMINI_API_KEY is placeholder. Running in mock mode.")

    async def analyze_evidence(
        self, 
        media_urls: List[str], 
        description_hint: str = ""
    ) -> MultimodalInsight:
        """
        Analyzes a set of media files to extract structured crisis insights.
        """
        if not media_urls:
            return MultimodalInsight(
                summary="No media provided.",
                destruction_detected=False,
                crowd_size_estimate=0,
                distress_level=0.0,
                detected_needs=[],
                confidence=0.0
            )

        logger.info("[Multimodal] Analyzing %d media attachments...", len(media_urls))
        
        # --- Placeholder/Mock Logic ---
        # In a real implementation, we would download or pass these URLs to Gemini's multimodal API.
        
        # MOCK: If text hint mentions 'broken' or 'flood', simulate high destruction detection.
        hint = description_hint.lower()
        has_destruction = any(word in hint for word in ["broken", "damage", "collapse", "ruin"])
        has_water = "flood" in hint or "water" in hint
        
        summary = f"Visual analysis of {len(media_urls)} files. "
        if has_destruction:
            summary += "Physical infrastructure damage detected. "
        if has_water:
            summary += "Significant standing water/flooding visible. "
            
        return MultimodalInsight(
            summary=summary,
            destruction_detected=has_destruction,
            crowd_size_estimate=50 if "crowd" in hint else 0,
            distress_level=0.8 if "cry" in hint or "help" in hint else 0.4,
            detected_needs=["shelter"] if has_destruction else ["water_sanitation"] if has_water else [],
            confidence=0.9 if self.enabled else 0.5,
            population_affected=200 if "200" in hint else 0
        )

# Global singleton
multimodal_preprocessor = MultimodalPreprocessor()
