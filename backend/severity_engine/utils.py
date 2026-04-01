from __future__ import annotations


def clamp01(value: float) -> float:
    return max(0.0, min(1.0, float(value)))


def safe_float(value: object, default: float = 0.0) -> float:
    try:
        return float(value)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return default
