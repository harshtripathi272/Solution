import json
import logging
from pathlib import Path
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)

class CommunityResolver:
    """
    Resolves raw text or region tags against a predefined list of target communities.
    If a target community is detected, returns its metadata (including precise lat/lon)
    to override generic country-level coordinates.
    """
    def __init__(self, data_file: Optional[Path] = None):
        if data_file is None:
            # Default to backend/data/communities.json
            data_file = Path(__file__).resolve().parents[2] / "data" / "communities.json"
        
        self.communities = []
        try:
            if data_file.exists():
                with open(data_file, "r", encoding="utf-8") as f:
                    self.communities = json.load(f)
                logger.info("[CommunityResolver] Loaded %d target communities.", len(self.communities))
            else:
                logger.warning("[CommunityResolver] Data file not found at %s", data_file)
        except Exception as e:
            logger.error("[CommunityResolver] Failed to load communities.json: %s", e)

    def resolve(self, text: str) -> Optional[Dict[str, Any]]:
        """
        Check if any community keywords exist in the provided text.
        Returns the community dictionary on first match, or None.
        """
        if not text:
            return None
            
        text_lower = text.lower()
        
        for comm in self.communities:
            keywords = comm.get("keywords", [])
            for kw in keywords:
                if kw.lower() in text_lower:
                    logger.debug("[CommunityResolver] Matched community %s with keyword '%s'", comm.get("id"), kw)
                    return comm
        return None

# Singleton instance for easy import
community_resolver = CommunityResolver()
