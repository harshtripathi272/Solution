from __future__ import annotations

from collections import defaultdict, deque
from datetime import datetime, timezone

from severity_engine.constants import TREND_BONUS_MAX, TREND_BONUS_MIN
from severity_engine.utils import clamp01


class TemporalTracker:
    def __init__(self) -> None:
        self._history: dict[str, deque[tuple[datetime, float]]] = defaultdict(lambda: deque(maxlen=64))

    def key_for(self, event) -> str:
        geohash = getattr(event, "geohash", "") or "unknown"
        need_type = getattr(event, "need_type", "other")
        return f"{geohash}:{need_type}"

    def record(self, key: str, ts: datetime, score: float) -> None:
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)
        self._history[key].append((ts, clamp01(score)))

    def trend_bonus(self, key: str) -> float:
        points = list(self._history.get(key, []))
        if len(points) < 3:
            return 0.0

        # Approximate second derivative from last 3 points.
        s1 = points[-3][1]
        s2 = points[-2][1]
        s3 = points[-1][1]
        second_derivative = s3 - (2 * s2) + s1
        if second_derivative <= 0:
            return 0.0

        # Scale to [0.10, 0.20] for positive acceleration.
        scaled = min(1.0, second_derivative / 0.25)
        return round(TREND_BONUS_MIN + (TREND_BONUS_MAX - TREND_BONUS_MIN) * scaled, 4)

    def apply_acute_inactivity_decay(self, event_ts: datetime, acute: float) -> float:
        now = datetime.now(timezone.utc)
        ts = event_ts if event_ts.tzinfo else event_ts.replace(tzinfo=timezone.utc)
        hours_since_signal = max(0.0, (now - ts).total_seconds() / 3600.0)
        if hours_since_signal <= 48.0:
            return acute
        # Additional exponential taper after 48h without fresh signal.
        extra_hours = hours_since_signal - 48.0
        decayed = acute * (2.718281828 ** (-0.03 * extra_hours))
        return clamp01(decayed)

    def apply_feedback_adjustment(self, score: float, feedback: str | None) -> float:
        if not feedback:
            return clamp01(score)
        fb = feedback.strip().lower()
        if fb == "resolved":
            return clamp01(score * 0.5)
        if fb == "worsened":
            return clamp01(score * 1.3)
        return clamp01(score)


temporal_tracker = TemporalTracker()
