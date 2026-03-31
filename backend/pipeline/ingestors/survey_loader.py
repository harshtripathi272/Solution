import csv
import json
import logging
from datetime import datetime, timezone
from pathlib import Path

from pipeline.core.schemas import IngestionLocation, UnifiedIngestionEvent

logger = logging.getLogger(__name__)


class SurveyDataLoader:
    """Loads local NGO survey or field files (CSV/JSON) into normalized ingestion events."""

    def load_file(self, file_path: str) -> list[UnifiedIngestionEvent]:
        path = Path(file_path)
        if not path.exists():
            raise FileNotFoundError(f"File not found: {file_path}")

        if path.suffix.lower() == ".csv":
            rows = self._load_csv(path)
        elif path.suffix.lower() == ".json":
            rows = self._load_json(path)
        else:
            raise ValueError("Only .csv and .json files are supported")

        events: list[UnifiedIngestionEvent] = []
        for idx, row in enumerate(rows):
            try:
                lat = float(row["latitude"])
                lon = float(row["longitude"])
                need_type = str(row.get("need_type", "other"))
                severity = str(row.get("severity", "moderate"))
                source = str(row.get("source", "NGO_SURVEY"))
                confidence = float(row.get("confidence_score", 0.7))
                timestamp = self._parse_timestamp(row.get("timestamp"))
                description = str(row.get("description", "NGO survey update"))

                event_id = str(row.get("id", f"SURVEY-{path.stem}-{idx}"))
                events.append(
                    UnifiedIngestionEvent(
                        id=event_id,
                        location=IngestionLocation(latitude=lat, longitude=lon),
                        need_type=need_type,
                        severity=severity,
                        timestamp=timestamp,
                        source=source,
                        confidence_score=max(0.0, min(1.0, confidence)),
                        description=description,
                        metadata={"file": str(path), **{k: v for k, v in row.items() if k not in {"latitude", "longitude", "need_type", "severity", "timestamp", "source", "confidence_score", "description"}}},
                    )
                )
            except Exception as exc:
                logger.warning("[SurveyLoader] skipping row %s due to parse error: %s", idx, exc)

        logger.info("[SurveyLoader] loaded %d normalized events from %s", len(events), file_path)
        return events

    def _load_csv(self, path: Path) -> list[dict]:
        with path.open("r", encoding="utf-8") as f:
            return list(csv.DictReader(f))

    def _load_json(self, path: Path) -> list[dict]:
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, list):
            return data
        if isinstance(data, dict) and isinstance(data.get("rows"), list):
            return data["rows"]
        raise ValueError("JSON file must be a list of objects or {'rows': [...]} structure")

    def _parse_timestamp(self, value) -> datetime:
        if isinstance(value, str) and value:
            try:
                parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
                if parsed.tzinfo is None:
                    parsed = parsed.replace(tzinfo=timezone.utc)
                return parsed.astimezone(timezone.utc)
            except Exception:
                pass
        return datetime.now(timezone.utc)
