"""
Extraction Strategy Router — intelligent NER vs. GLiNER matching.

Instead of always running expensive NVIDIA LLM for every event, this router:
  1. Attempts fast, deterministic extraction using GLiNER (Zero-Shot offline NER)
  2. Only falls back to NVIDIA NER when confidence is low or extraction fails
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

# Optional dependencies loaded inside methods to avoid heavy module initialization
GLiNER = None

logger = logging.getLogger(__name__)


class ExtractionStrategy(str, Enum):
    """Per-ingestor extraction preference."""
    NEVER = "never"                # Never run NER (ingestor provides all data)
    PATTERN_ONLY = "pattern_only"  # Fast GLiNER/pattern matching only
    HYBRID = "hybrid"              # GLiNER first, NVIDIA NER if low confidence
    ALWAYS = "always"              # Always run NVIDIA NER regardless


@dataclass
class ExtractionConfig:
    """Configuration for a given ingestor's extraction needs."""
    strategy: ExtractionStrategy = ExtractionStrategy.HYBRID
    confidence_threshold: float = 0.75  # Run NVIDIA NER if confidence below this
    cache_results: bool = True  # Cache NER results for identical text
    reason: str = ""  # Rationale for this configuration


# Per-ingestor configuration registry
INGESTOR_EXTRACTION_CONFIG: dict[str, ExtractionConfig] = {
    "GDACS": ExtractionConfig(strategy=ExtractionStrategy.NEVER, reason="Already has coordinates and mapped event types"),
    "NDMA": ExtractionConfig(strategy=ExtractionStrategy.NEVER, reason="Government alerts with structured format"),
    "PIB_RSS": ExtractionConfig(strategy=ExtractionStrategy.NEVER, reason="Official bulletin feed with metadata"),
    "IMD_ALERTS": ExtractionConfig(strategy=ExtractionStrategy.NEVER, reason="Weather alerts structure labels"),
    "RELIEFWEB": ExtractionConfig(strategy=ExtractionStrategy.PATTERN_ONLY, confidence_threshold=0.70, cache_results=True, reason="Humanitarian feed"),
    "NGO_REPORTS": ExtractionConfig(strategy=ExtractionStrategy.HYBRID, confidence_threshold=0.70, cache_results=True, reason="Unstructured text"),
    "NEWS_API": ExtractionConfig(strategy=ExtractionStrategy.HYBRID, confidence_threshold=0.65, cache_results=True, reason="News articles"),
    "KOBO": ExtractionConfig(strategy=ExtractionStrategy.HYBRID, confidence_threshold=0.60, cache_results=False, reason="User-submitted variance"),
    "GLOBAL_RSS": ExtractionConfig(strategy=ExtractionStrategy.HYBRID, confidence_threshold=0.65, cache_results=True, reason="Deep-scraped news"),
    "MASTODON": ExtractionConfig(strategy=ExtractionStrategy.HYBRID, confidence_threshold=0.60, cache_results=False, reason="Social media posts"),
}


class GLiNERExtractor:
    """Zero-Shot NER extraction using GLiNER, replacing hardcoded pattern matching."""
    
    def __init__(self):
        self.model = None
        self.labels = ["disaster", "location", "infrastructure damage", "human impact"]
        
    def _load_model(self):
        if not self.model:
            try:
                from gliner import GLiNER
                global_GLiNER = GLiNER
            except ImportError:
                global_GLiNER = None
                
            repo_id = "urchade/gliner_base" if global_GLiNER is not None else None
            
            if global_GLiNER is not None:
                # Silence annoying HuggingFace warnings and download logs
                import os
                import warnings
                import logging as py_logging
                from pathlib import Path
                
                os.environ["HF_HUB_DISABLE_SYMLINKS_WARNING"] = "1"
                warnings.filterwarnings("ignore", category=UserWarning, module="huggingface_hub")
                py_logging.getLogger("huggingface_hub").setLevel(py_logging.ERROR)
                
                cache_dir = os.getenv("HF_HOME", os.path.expanduser("~/.cache/huggingface/hub"))
                folder_name = "models--" + repo_id.replace("/", "--")
                model_path = Path(cache_dir) / folder_name
                
                exists_locally = model_path.exists()
                
                if not exists_locally:
                    print(f"\n[GLiNER] ⚠️ Model '{repo_id}' not found locally. Downloading ~150MB now. Please wait...")
                    logger.info("Downloading urchade/gliner_base model...")
                else:
                    print(f"\n[GLiNER] ✅ Model found locally! Loading instantly offline...")
                    logger.debug("Loading cached urchade/gliner_base model...")
                    
                # Use local_files_only=True to prevent "Fetching X files" logs if already cached
                self.model = GLiNER.from_pretrained(repo_id, local_files_only=exists_locally)
                logger.info("[GLiNERExtractor] GLiNER Model Ready.")

    def extract(self, text: str) -> dict:
        """Fast offline extraction of labels from text via Matrix Multiplication."""
        empty_result = {"need_type": None, "severity": None, "places": [], "confidence": 0.0}
            
        if not text:
            return empty_result
            
        self._load_model()
        if not self.model:
            logger.warning("[GLiNERExtractor] gliner not installed. Run 'pip install gliner'.")
            return empty_result
        
        # Limit text length to prevent quadratic processing explosion
        truncated_text = text[:800]
        entities = self.model.predict_entities(truncated_text, self.labels)
        
        result = {"need_type": None, "severity": None, "places": [], "confidence": 0.0}
        
        for entity in entities:
            label = entity["label"]
            word = entity["text"].lower()
            score = entity["score"]
            
            # Map both 'disaster' and 'emergency' to our Crisis Type logic
            if label in ["disaster", "emergency"] and score > 0.40:
                mapped_type = self._map_to_internal_need(word)
                if mapped_type:
                    result["need_type"] = mapped_type
                    result["confidence"] = max(result.get("confidence", 0.0), score)
                elif not result["need_type"]:
                    result["need_type"] = word
                    result["confidence"] = max(result.get("confidence", 0.0), score)
            
            elif label == "location" and score > 0.65:
                # Filter out generic noise if it's too long or doesn't look like a proper noun
                if entity["text"] not in result["places"]:
                    result["places"].append(entity["text"])
                
            elif label in ["infrastructure damage", "human impact"] and score > 0.35:
                # Severity analysis based on keywords in the extracted span
                if any(warn in word for warn in ["dead", "death", "destroy", "critical", "sever", "emergency", "fatal", "massive"]):
                    result["severity"] = "red"
                elif any(warn in word for warn in ["injur", "damage", "alert", "warn", "high", "widespread", "strand", "breach", "affect"]):
                    if result["severity"] != "red":
                        result["severity"] = "orange"
                else:
                    if not result["severity"]:
                        result["severity"] = "green"

        return result

    def _map_to_internal_need(self, word: str) -> str:
        word = word.lower()
        if any(kw in word for kw in ["flood", "water", "inundat", "rain", "torrent", "river", "breach", "overflow"]): 
            return "flood"
        if any(kw in word for kw in ["cyclon", "hurrican", "storm", "wind", "typhoon"]): 
            return "cyclone"
        if any(kw in word for kw in ["earthquak", "tremor", "shak", "seismic"]): 
            return "earthquake"
        if any(kw in word for kw in ["fire", "blaze", "burn", "flame"]): 
            return "fire"
        if any(kw in word for kw in ["medic", "diseas", "outbreak", "health", "hospit", "virus"]): 
            return "medical"
        if any(kw in word for kw in ["drought", "dry", "water scarcity", "crop fail"]): 
            return "drought"
        if any(kw in word for kw in ["food", "hunger", "famin", "starv"]): 
            return "food"
        return "other"


class ExtractionStrategyRouter:
    """Routes extraction decisions: GLiNER → hybrid → NVIDIA NER based on source."""
    
    def __init__(self):
        self._local_extractor = GLiNERExtractor()
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
        Decide whether to run full NVIDIA NER extraction.
        
        Returns False if:
          - Ingestor config says NEVER
          - GLiNER succeeded with high confidence
          - Cached result available
        
        Returns True if:
          - Ingestor config says ALWAYS
          - GLiNER ambiguous or failed, confidence low -> Trips NVIDIA LLM
        """
        config = INGESTOR_EXTRACTION_CONFIG.get(
            event.source.split("_")[0],
            ExtractionConfig(strategy=ExtractionStrategy.HYBRID)
        )
        
        if config.strategy == ExtractionStrategy.NEVER:
            logger.debug("[ExtractionRouter] Skipping NER for %s (config=NEVER)", event.source)
            return False
        
        if config.strategy == ExtractionStrategy.ALWAYS:
            return True
        
        # Check cache first
        if config.cache_results:
            cache_key = self._cache_key(event.description)
            if cache_key in self._ner_cache:
                logger.debug("[ExtractionRouter] Cache hit for %s", event.id)
                cached = self._ner_cache[cache_key]
                if cached.get("need_type"):
                    event = event.model_copy(update={"need_type": cached["need_type"]})
                if cached.get("severity"):
                    event = event.model_copy(update={"severity": cached["severity"]})
                if cached.get("places"):
                    event = event.model_copy(update={"metadata": {**event.metadata, "places": cached["places"]}})
                return False  
        
        # HYBRID / PATTERN_ONLY: Try GLiNER zero-shot extraction first
        if config.strategy in (ExtractionStrategy.HYBRID, ExtractionStrategy.PATTERN_ONLY):
            
            # Using GLiNER instead of hardcoded pattern matcher
            gliner_run = self._local_extractor.extract(event.description)
            
            ext_need_type = gliner_run["need_type"]
            ext_severity = gliner_run["severity"]
            ext_places = gliner_run["places"]
            ext_confidence = gliner_run["confidence"]
            
            logger.debug(
                "[ExtractionRouter] GLiNER extracted %s/%s/Places:%d (conf=%.2f) for %s",
                ext_need_type, ext_severity, len(ext_places), ext_confidence, event.id
            )
            
            # If GLiNER succeeded and confidence above threshold
            if ext_confidence >= config.confidence_threshold:
                updates = {}
                if ext_need_type:
                    updates["need_type"] = ext_need_type
                if ext_severity:
                    updates["severity"] = ext_severity
                if ext_places:
                    # Storing places in metadata to be consumed globally by Geocoder
                    updates["metadata"] = {**event.metadata, "places": ext_places}
                    
                if updates:
                    event = event.model_copy(update=updates)
                
                # Cache the GLiNER result
                if config.cache_results:
                    cache_key = self._cache_key(event.description)
                    self._ner_cache[cache_key] = {
                        "need_type": ext_need_type,
                        "severity": ext_severity,
                        "places": ext_places,
                    }
                
                logger.debug("[ExtractionRouter] Using GLiNER result (conf %.2f >= %.2f); skipping NVIDIA NER", ext_confidence, config.confidence_threshold)
                return False
            
            # Confidence too low
            if config.strategy == ExtractionStrategy.PATTERN_ONLY:
                logger.debug("[ExtractionRouter] GLiNER confidence low, but config is PATTERN_ONLY. Skipping NVIDIA NER.")
                return False 
            
            logger.debug("[ExtractionRouter] GLiNER confidence %.2f < threshold %.2f; Tripwire triggered, routing to NVIDIA NER", ext_confidence, config.confidence_threshold)
            return True
        
        return False
    
    async def extract_with_strategy(
        self,
        event: UnifiedIngestionEvent,
    ) -> dict | None:
        """
        Extract using configured strategy. Returns dict with:
          - need_type, severity, places, confidence_score
        """
        should_run = await self.should_run_ner(event)
        
        if not should_run:
            logger.debug("[ExtractionRouter] Skipping NVIDIA extraction for %s", event.id)
            return None
        
        logger.info("[ExtractionRouter] Running full NVIDIA NER for %s (source=%s)", event.id, event.source)
        
        ner_result = await ner_extractor.extract(event.description)
        if ner_result:
            config = INGESTOR_EXTRACTION_CONFIG.get(event.source.split("_")[0], ExtractionConfig())
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
