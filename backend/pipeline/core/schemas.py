from pydantic import BaseModel, Field, model_validator
from typing import List, Optional, Dict, Any
from datetime import datetime, timezone
from enum import Enum
import uuid

# Centroid of India used as a fallback when an ingestor has no real coordinates.
# Events carrying these exact coordinates are flagged for NER + geocoding.
FALLBACK_INDIA_LAT = 20.5937
FALLBACK_INDIA_LON = 78.9629
_FALLBACK_TOLERANCE = 0.01  # degrees (~1 km)

class SeverityLevel(str, Enum):
    CRITICAL = "red"
    HIGH = "orange"
    MODERATE = "green"
    UNKNOWN = "unknown"


class NeedTemporality(str, Enum):
    CHRONIC = "chronic"
    ACUTE = "acute"

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


class ActivationWindow(BaseModel):
    start_at: datetime
    end_at: datetime


class DocumentMetadata(BaseModel):
    source_ngo: str
    pdf_url: str
    publication_date: Optional[datetime] = None
    sha256_hash: str

class CrisisEvent(BaseModel):
    id: str
    source: str # e.g., 'GDACS', 'NDMA', 'TWITTER', 'CITIZEN'
    tier: int # 1 = Official, 2 = Citizen, 3 = Contextual
    timestamp: datetime
    type: CrisisType
    severity: SeverityLevel
    location: LocationMetadata
    description: str
    need_temporality: NeedTemporality = NeedTemporality.ACUTE
    activation_window: Optional[ActivationWindow] = None
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


class IngestionLocation(BaseModel):
    latitude: float
    longitude: float


class UnifiedIngestionEvent(BaseModel):
    """Source-agnostic normalized ingestion payload used by all Phase 1 ingestors."""
    id: str
    location: IngestionLocation
    need_type: str
    severity: str
    timestamp: datetime
    source: str
    need_temporality: NeedTemporality = NeedTemporality.ACUTE
    confidence_score: float = Field(ge=0.0, le=1.0)
    description: str = ""
    metadata: Dict[str, Any] = Field(default_factory=dict)
    document_metadata: Optional[DocumentMetadata] = None

    # --- Unification pipeline fields (set by unified_pipeline.py) ---
    # 5-char geohash of the event location (~5 km cell). Populated after geocoding.
    geohash: str = ""
    # Administrative granularity at which location was resolved.
    admin_level: str = "country"   # village | block | district | state | country
    # Estimated number of people affected (populated from source metadata where available).
    population_affected: int = 0
    # Trust tier of the source: 1=official, 2=crowd/ngo, 3=social/contextual.
    source_tier: int = 2
    # True when the ingestor had no real coordinates — triggers NER + geocoding.
    needs_geocoding: bool = False

    @model_validator(mode="after")
    def _auto_flag_geocoding(self) -> "UnifiedIngestionEvent":
        """Auto-set needs_geocoding when the ingestor fell back to India centroid."""
        lat_fallback = abs(self.location.latitude  - FALLBACK_INDIA_LAT) < _FALLBACK_TOLERANCE
        lon_fallback = abs(self.location.longitude - FALLBACK_INDIA_LON) < _FALLBACK_TOLERANCE
        if lat_fallback and lon_fallback and not self.needs_geocoding:
            object.__setattr__(self, "needs_geocoding", True)
        return self


def infer_crisis_type(need_type: str) -> CrisisType:
    value = (need_type or "").strip().lower()
    if "flood" in value:
        return CrisisType.FLOOD
    if "cyclone" in value or "storm" in value:
        return CrisisType.CYCLONE
    if "earthquake" in value or "quake" in value:
        return CrisisType.EARTHQUAKE
    if "medical" in value or "health" in value or "disease" in value:
        return CrisisType.MEDICAL
    if "fire" in value or "wildfire" in value:
        return CrisisType.FIRE
    if "violence" in value or "conflict" in value:
        return CrisisType.VIOLENCE
    return CrisisType.OTHER


def infer_severity(value: str) -> SeverityLevel:
    raw = (value or "").strip().lower()
    if raw in {"critical", "red", "severe", "extreme"}:
        return SeverityLevel.CRITICAL
    if raw in {"high", "orange", "major"}:
        return SeverityLevel.HIGH
    if raw in {"moderate", "green", "medium", "low"}:
        return SeverityLevel.MODERATE
    return SeverityLevel.UNKNOWN


def to_crisis_event(event: UnifiedIngestionEvent, tier: int, verified: bool) -> CrisisEvent:
    crisis_type = infer_crisis_type(event.need_type)
    severity = infer_severity(event.severity)
    needs_medical = crisis_type == CrisisType.MEDICAL
    needs_rescue = crisis_type in {CrisisType.FLOOD, CrisisType.EARTHQUAKE, CrisisType.CYCLONE, CrisisType.FIRE}

    geohash = event.geohash
    if not geohash:
        try:
            from pipeline.processing.geohash import encode as geohash_encode
            geohash = geohash_encode(event.location.latitude, event.location.longitude, precision=5)
        except Exception:
            geohash = ""

    if not geohash:
        geohash = f"coord:{event.location.latitude:.3f}:{event.location.longitude:.3f}"
    description = event.description or f"{event.need_type} alert from {event.source}"
    severity_meta = (event.metadata or {}).get("severity_engine", {})
    urgency = float(severity_meta.get("composite_urgency", 0.0) or 0.0)
    classification = str(severity_meta.get("classification", "")).strip()

    if urgency > 0:
        min_volunteers = max(3, int(round(urgency * 20)))
    elif classification == "Extreme":
        min_volunteers = 16
    elif classification == "Severe":
        min_volunteers = 10
    else:
        min_volunteers = 10 if severity == SeverityLevel.CRITICAL else 3

    return CrisisEvent(
        id=event.id or str(uuid.uuid4()),
        source=event.source,
        tier=tier,
        timestamp=event.timestamp.astimezone(timezone.utc),
        type=crisis_type,
        severity=severity,
        need_temporality=event.need_temporality,
        location=LocationMetadata(
            latitude=event.location.latitude,
            longitude=event.location.longitude,
            geohash=geohash,
            region_name=str(event.metadata.get("region", "unknown")),
            address=event.metadata.get("address"),
            radius_km=float(event.metadata.get("radius_km", 10.0)),
        ),
        description=description,
        is_verified=verified,
        skills_required=SkillMatrix(
            requires_medical=needs_medical,
            requires_rescue=needs_rescue,
            requires_logistics=severity in {SeverityLevel.CRITICAL, SeverityLevel.HIGH},
            requires_counseling=crisis_type in {CrisisType.VIOLENCE, CrisisType.MEDICAL},
            min_volunteers_needed=min_volunteers,
        ),
        raw_data={
            **event.metadata,
            "document_metadata": event.document_metadata.model_dump() if event.document_metadata else None,
        },
    )
