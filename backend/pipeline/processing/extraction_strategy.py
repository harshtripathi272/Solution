"""
Extraction Strategy Router — intelligent NER vs. pattern matching.

Instead of always running expensive NVIDIA LLM for every event, this router:
  1. Attempts fast, deterministic pattern matching first
  2. Only falls back to NVIDIA NER when confidence is low or patterns fail
  3. Caches NER results for identical/similar text snippets
  4. Allows per-ingestor configuration of extraction requirements

This prevents wasting NVIDIA token quota and API calls on structured/high-confidence sources.
"""

from __future__ import annotations

import hashlib
import logging
from dataclasses import dataclass
from enum import Enum
from typing import Optional

from pipeline.core.schemas import UnifiedIngestionEvent
from pipeline.processing.ner import ner_extractor

logger = logging.getLogger(__name__)


class ExtractionStrategy(str, Enum):
    """Per-ingestor extraction preference."""
    NEVER = "never"              # Never run NER (ingestor provides all data)
    PATTERN_ONLY = "pattern_only"  # Fast pattern matching only
    HYBRID = "hybrid"             # Pattern first, NER if low confidence
    ALWAYS = "always"             # Always run NER regardless


@dataclass
class ExtractionConfig:
    """Configuration for a given ingestor's extraction needs."""
    strategy: ExtractionStrategy = ExtractionStrategy.HYBRID
    confidence_threshold: float = 0.75  # Run NER if event confidence below this
    cache_results: bool = True  # Cache NER results for identical text
    reason: str = ""  # Rationale for this configuration


# Per-ingestor configuration registry
INGESTOR_EXTRACTION_CONFIG: dict[str, ExtractionConfig] = {
    # Official sources with clean structured data — no NER needed
    "GDACS": ExtractionConfig(
        strategy=ExtractionStrategy.NEVER,
        reason="Already has coordinates and mapped event types"
    ),
    "NDMA": ExtractionConfig(
        strategy=ExtractionStrategy.NEVER,
        reason="Government alerts with structured format"
    ),
    "PIB_RSS": ExtractionConfig(
        strategy=ExtractionStrategy.NEVER,
        reason="Official bulletin feed with structured metadata"
    ),
    "IMD_ALERTS": ExtractionConfig(
        strategy=ExtractionStrategy.NEVER,
        reason="Weather alerts provide structured event labels"
    ),
    "RELIEFWEB": ExtractionConfig(
        strategy=ExtractionStrategy.PATTERN_ONLY,
        confidence_threshold=0.70,
        cache_results=True,
        reason="Semi-structured humanitarian feed with consistent taxonomy"
    ),
    
    # Crowd-sourced / text-based sources — need NER but benefit from caching
    "NGO_REPORTS": ExtractionConfig(
        strategy=ExtractionStrategy.HYBRID,
        confidence_threshold=0.70,
        cache_results=True,
        reason="Unstructured text, high duplicate rate across scraped sources"
    ),
    "NEWS_API": ExtractionConfig(
        strategy=ExtractionStrategy.HYBRID,
        confidence_threshold=0.65,
        cache_results=True,
        reason="News articles often cover same event; pattern matching handles common phrases"
    ),
    
    # Survey/citizen reports — often ambiguous, needs NER but with speed optimization
    "KOBO": ExtractionConfig(
        strategy=ExtractionStrategy.HYBRID,
        confidence_threshold=0.60,
        cache_results=False,
        reason="User-submitted, high variance, less repetition"
    ),
    
    # Real-time community-focused free sources
    "GLOBAL_RSS": ExtractionConfig(
        strategy=ExtractionStrategy.HYBRID,
        confidence_threshold=0.65,
        cache_results=True,
        reason="Deep-scraped news articles; high duplicate rate across sources; already filtered for crisis keywords"
    ),
    "MASTODON": ExtractionConfig(
        strategy=ExtractionStrategy.HYBRID,
        confidence_threshold=0.60,
        cache_results=False,
        reason="Social media with high variance; user-submitted with hashtag pre-filtering reduces false positives"
    ),
}


class PatternMatcher:
    """Fast, deterministic extraction for common crisis types and locations."""
    
    CRISIS_PATTERNS = {
        "flood": ["flood", "waterlogging", "inundation", "deluge", "submerged"],
        "cyclone": ["cyclone", "hurricane", "typhoon", "windstorm", "tropical storm"],
        "earthquake": ["earthquake", "seismic", "tremor", "aftershock", "quake"],
        "fire": ["fire", "blaze", "wildfire", "forest fire", "conflagration"],
        "drought": ["drought", "dry", "drying", "water scarcity", "shortage"],
        "landslide": ["landslide", "mudslide", "soil slip", "debris flow"],
        "epidemic": ["epidemic", "outbreak", "disease", "infection", "covid", "dengue", "malaria"],
        "medical": ["medical", "health", "hospital", "disease", "injured", "casualties"],
        "water_sanitation": ["water", "sanitation", "drinking water", "WASH", "hygiene"],
        "food": ["food", "hunger", "famine", "crop", "farming"],
    }
    
    SEVERITY_INDICATORS = {
        "critical": ["critical", "severe", "emergency", "disaster", "catastrophic", "dead", "death", "casualties"],
        "high": ["alert", "warning", "significant", "extensive", "widespread", "injured", "damage"],
        "moderate": ["alert", "concern", "risk", "concern", "assess"],
        "low": ["minor", "small", "limited", "report"],
    }
    
    @staticmethod
    def extract_need_type(text: str) -> Optional[str]:
        """Fast pattern matching for crisis type. Returns None if ambiguous."""
        if not text:
            return None
        
        text_lower = text.lower()
        matches = {}
        
        for crisis_type, keywords in PatternMatcher.CRISIS_PATTERNS.items():
            for keyword in keywords:
                if keyword in text_lower:
                    matches[crisis_type] = matches.get(crisis_type, 0) + 1
        
        if not matches:
            return None
        
        # Return only if clear winner (not ambiguous)
        top_match = max(matches, key=matches.get)
        top_count = matches[top_match]
        
        # Ambiguous if multiple types tied or only weak matches
        if len(matches) > 1 and top_count <= 1:
            return None  # Ambiguous — should use NER
        
        return top_match
    
    @staticmethod
    def extract_severity(text: str) -> Optional[str]:
        """Fast pattern matching for severity level."""
        if not text:
            return None
        
        text_lower = text.lower()
        matches = {}
        
        for severity, keywords in PatternMatcher.SEVERITY_INDICATORS.items():
            for keyword in keywords:
                if keyword in text_lower:
                    matches[severity] = matches.get(severity, 0) + 1
        
        if not matches:
            return None
        
        # Return only if clear winner; otherwise return None for NER
        top_match = max(matches, key=matches.get)
        if len(matches) > 1 and matches[top_match] <= 1:
            return None  # Ambiguous
        
        return top_match
    
    @staticmethod
    def get_pattern_confidence(text: str) -> float:
        """Get confidence of pattern extraction (0.0-1.0)."""
        word_count = len(text.split())
        
        if word_count < 10:
            return 0.3  # Too short, unreliable
        
        # More specific patterns → higher confidence
        crisis_matches = 0
        for keywords in PatternMatcher.CRISIS_PATTERNS.values():
            for keyword in keywords:
                if keyword in text.lower():
                    crisis_matches += 1
        
        severity_matches = 0
        for keywords in PatternMatcher.SEVERITY_INDICATORS.values():
            for keyword in keywords:
                if keyword in text.lower():
                    severity_matches += 1
        
        # Confidence: base + keyword density
        base_confidence = 0.5
        keyword_boost = min(0.4, (crisis_matches + severity_matches * 0.5) / 10.0)
        
        return min(1.0, base_confidence + keyword_boost)


class ExtractionStrategyRouter:
    """Routes extraction decisions: pattern → hybrid → always based on source."""
    
    def __init__(self):
        self._pattern_matcher = PatternMatcher()
        self._ner_cache: dict[str, dict] = {}  # text_hash → extraction result
    
    def _cache_key(self, text: str) -> str:
        """Generate cache key from text snippet."""
        return hashlib.md5(text[:256].encode()).hexdigest()
    
    async def should_run_ner(
        self,
        event: UnifiedIngestionEvent,
        force_noinput: bool = False,
    ) -> bool:
        """
        Decide whether to run full NER extraction.
        
        Returns False if:
          - Ingestor config says NEVER
          - Pattern matching succeeded with high confidence
          - Cached result available
        
        Returns True if:
          - Ingestor config says ALWAYS
          - Pattern matching ambiguous or failed, confidence low
        """
        config = INGESTOR_EXTRACTION_CONFIG.get(
            event.source.split("_")[0],  # e.g., "NGO_REPORTS" → "NGO"
            ExtractionConfig(strategy=ExtractionStrategy.HYBRID)
        )
        
        if config.strategy == ExtractionStrategy.NEVER:
            logger.debug(
                "[ExtractionRouter] Skipping NER for %s (config=NEVER)",
                event.source
            )
            return False
        
        if config.strategy == ExtractionStrategy.ALWAYS:
            return True
        
        # Check cache first
        if config.cache_results:
            cache_key = self._cache_key(event.description)
            if cache_key in self._ner_cache:
                logger.debug("[ExtractionRouter] Cache hit for %s", event.id)
                # Apply cached result to event
                cached = self._ner_cache[cache_key]
                if cached.get("need_type"):
                    event = event.model_copy(update={"need_type": cached["need_type"]})
                if cached.get("severity"):
                    event = event.model_copy(update={"severity": cached["severity"]})
                return False  # Don't run NER if cached
        
        # HYBRID: Try pattern matching first
        if config.strategy == ExtractionStrategy.HYBRID or \
           config.strategy == ExtractionStrategy.PATTERN_ONLY:
            
            pattern_need_type = self._pattern_matcher.extract_need_type(
                event.description
            )
            pattern_severity = self._pattern_matcher.extract_severity(
                event.description
            )
            pattern_confidence = self._pattern_matcher.get_pattern_confidence(
                event.description
            )
            
            logger.debug(
                "[ExtractionRouter] Pattern extracted %s/%s (conf=%.2f) for %s",
                pattern_need_type, pattern_severity, pattern_confidence, event.id
            )
            
            # If pattern succeeded and confidence above threshold, use it
            if pattern_confidence >= config.confidence_threshold:
                if pattern_need_type:
                    event = event.model_copy(update={"need_type": pattern_need_type})
                if pattern_severity:
                    event = event.model_copy(update={"severity": pattern_severity})
                
                # Cache the result
                if config.cache_results:
                    cache_key = self._cache_key(event.description)
                    self._ner_cache[cache_key] = {
                        "need_type": pattern_need_type,
                        "severity": pattern_severity,
                    }
                
                logger.debug(
                    "[ExtractionRouter] Using pattern result (conf >= %.2f); skipping NER",
                    config.confidence_threshold
                )
                return False
            
            # Pattern confidence too low — use NER
            if config.strategy == ExtractionStrategy.PATTERN_ONLY:
                logger.debug(
                    "[ExtractionRouter] Pattern confidence too low; "
                    "config says PATTERN_ONLY, so returning None"
                )
                return False  # Don't run NER if config forbids
            
            logger.debug(
                "[ExtractionRouter] Pattern confidence %.2f < threshold %.2f; "
                "falling back to NER",
                pattern_confidence, config.confidence_threshold
            )
            return True
        
        return False
    
    async def extract_with_strategy(
        self,
        event: UnifiedIngestionEvent,
    ) -> dict | None:
        """
        Extract using configured strategy. Returns dict with:
          - need_type, severity, places, confidence_score
        
        Or None if extraction failed/not needed.
        """
        should_run = await self.should_run_ner(event)
        
        if not should_run:
            logger.debug("[ExtractionRouter] Skipping extraction for %s", event.id)
            return None
        
        logger.info(
            "[ExtractionRouter] Running full NER for %s (source=%s)",
            event.id, event.source
        )
        
        ner_result = await ner_extractor.extract(event.description)
        if ner_result:
            # Cache the result
            config = INGESTOR_EXTRACTION_CONFIG.get(
                event.source.split("_")[0],
                ExtractionConfig()
            )
            if config.cache_results:
                cache_key = self._cache_key(event.description)
                self._ner_cache[cache_key] = {
                    "need_type": ner_result.need_type,
                    "severity": ner_result.severity,
                    "places": ner_result.places,
                    "confidence": ner_result.confidence,
                }
            
            return {
                "need_type": ner_result.need_type,
                "severity": ner_result.severity,
                "places": ner_result.places,
                "confidence_score": ner_result.confidence,
            }
        
        return None


# Singleton
extraction_strategy_router = ExtractionStrategyRouter()
