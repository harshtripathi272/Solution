from pydantic import BaseModel, Field
from typing import List, Optional, Dict, Any
from datetime import datetime
from enum import Enum

class SeverityLevel(str, Enum):
    CRITICAL = "red"
    HIGH = "orange"
    MODERATE = "green"
    UNKNOWN = "unknown"

class CrisisType(str, Enum):
    FLOOD = "flood"
    CYCLONE = "cyclone"
    EARTHQUAKE = "earthquake"
    MEDICAL = "medical"
    VIOLENCE = "violence"
    FIRE = "fire"
    OTHER = "other"

class LocationMetadata(BaseModel):
    latitude: float
    longitude: float
    geohash: str
    region_name: str
    address: Optional[str] = None
    radius_km: Optional[float] = 10.0

class SkillMatrix(BaseModel):
    requires_medical: bool = False
    requires_rescue: bool = False
    requires_logistics: bool = False
    requires_counseling: bool = False
    min_volunteers_needed: int = 1

class CrisisEvent(BaseModel):
    id: str
    source: str # e.g., 'GDACS', 'NDMA', 'TWITTER', 'CITIZEN'
    tier: int # 1 = Official, 2 = Citizen, 3 = Contextual
    timestamp: datetime
    type: CrisisType
    severity: SeverityLevel
    location: LocationMetadata
    description: str
    is_verified: bool = False
    skills_required: SkillMatrix
    raw_data: Optional[Dict[str, Any]] = None # Storing the direct payload for debugging/NLP

    def generate_hash(self) -> str:
        """Creates a unique deterministic hash based on Time, Type, and coarse Geohash"""
        import hashlib
        # Use 5-character geohash (approx 4.9km x 4.9km grid) for temporal-spatial deduplication
        coarse_geo = self.location.geohash[:5] 
        event_day = self.timestamp.strftime('%Y-%m-%d')
        raw_str = f"{self.type.value}_{coarse_geo}_{event_day}"
        return hashlib.sha256(raw_str.encode()).hexdigest()
