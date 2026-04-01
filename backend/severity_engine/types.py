from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any


@dataclass
class SeverityResult:
    severity_acute: float
    severity_chronic: float
    composite_urgency: float
    reliability_score: float
    source_reliability: float
    detection_confidence: float
    trend_bonus: float
    gap_penalty: float
    classification: str
    color: str
    recommended_action: str
    recommended_response_time: str
    explanation: str

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)
