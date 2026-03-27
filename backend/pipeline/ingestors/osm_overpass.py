import logging
from typing import Any

import httpx

logger = logging.getLogger(__name__)


class OverpassEnricher:
    API_URL = "https://overpass-api.de/api/interpreter"

    async def enrich(self, lat: float, lon: float, radius_m: int = 5000) -> dict[str, Any]:
        query = f"""
[out:json][timeout:25];
(
  node["amenity"~"hospital|clinic|shelter"](around:{radius_m},{lat},{lon});
  way["amenity"~"hospital|clinic|shelter"](around:{radius_m},{lat},{lon});
  node["social_facility"~"shelter"](around:{radius_m},{lat},{lon});
);
out center 30;
""".strip()

        try:
            async with httpx.AsyncClient(timeout=20.0) as client:
                resp = await client.post(self.API_URL, data=query)
                resp.raise_for_status()
                data = resp.json()
        except Exception as exc:
            logger.warning("[Overpass] enrichment failed: %s", exc)
            return {"infrastructure": []}

        infra = []
        for element in data.get("elements", []):
            tags = element.get("tags", {})
            name = tags.get("name") or tags.get("amenity") or tags.get("social_facility") or "unknown"
            lat_val = element.get("lat") or (element.get("center") or {}).get("lat")
            lon_val = element.get("lon") or (element.get("center") or {}).get("lon")
            if lat_val is None or lon_val is None:
                continue
            infra.append(
                {
                    "name": name,
                    "type": tags.get("amenity") or tags.get("social_facility") or "unknown",
                    "latitude": lat_val,
                    "longitude": lon_val,
                }
            )

        return {"infrastructure": infra[:30]}
