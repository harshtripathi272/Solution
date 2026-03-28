import argparse
import asyncio
import os
from typing import Any

import httpx
from dotenv import load_dotenv


# NewsAPI (FIXED)
async def fetch_newsapi(client: httpx.AsyncClient, api_key: str, limit: int) -> list[dict[str, Any]]:
    url = "https://newsapi.org/v2/everything"

    params = {
        "q": "India",  
        "language": "en",
        "sortBy": "publishedAt",
        "pageSize": limit,
    }

    headers = {"X-Api-Key": api_key}

    resp = await client.get(url, params=params, headers=headers)

    print("STATUS:", resp.status_code)
    print("URL:", resp.url)

    resp.raise_for_status()
    data = resp.json()

    print("TOTAL:", data.get("totalResults"))

    items: list[dict[str, Any]] = []

    for article in data.get("articles", []):
        items.append(
            {
                "provider": "newsapi",
                "title": article.get("title", ""),
                "source": (article.get("source") or {}).get("name", "unknown"),
                "published": article.get("publishedAt", ""),
                "url": article.get("url", ""),
            }
        )

    return items


# -----------------------------
# NewsData (already correct)
# -----------------------------
async def fetch_newsdata(client: httpx.AsyncClient, api_key: str, limit: int) -> list[dict[str, Any]]:
    url = "https://newsdata.io/api/1/news"

    params = {
        "apikey": api_key,
        "country": "in",
        "language": "en",
    }

    resp = await client.get(url, params=params)
    resp.raise_for_status()
    data = resp.json()

    items: list[dict[str, Any]] = []

    for article in data.get("results", [])[:limit]:
        items.append(
            {
                "provider": "newsdata",
                "title": article.get("title", ""),
                "source": article.get("source_id", "unknown"),
                "published": article.get("pubDate", ""),
                "url": article.get("link", ""),
            }
        )

    return items


# -----------------------------
# MAIN
# -----------------------------
async def main() -> None:
    load_dotenv()

    parser = argparse.ArgumentParser(description="Test India-specific crisis news APIs")
    parser.add_argument(
        "--provider",
        choices=["newsapi", "newsdata", "both"],
        default="both",
    )
    parser.add_argument("--limit", type=int, default=5)

    args = parser.parse_args()

    newsapi_key = os.getenv("NEWS_API_KEY", "").strip()
    newsdata_key = os.getenv("NEWS_DATA_API_KEY", "").strip()

    async with httpx.AsyncClient(timeout=20.0) as client:
        all_items: list[dict[str, Any]] = []

        # NewsAPI
        if args.provider in {"newsapi", "both"}:
            if not newsapi_key:
                print("[newsapi] NEWS_API_KEY missing")
            else:
                try:
                    items = await fetch_newsapi(client, newsapi_key, args.limit)
                    all_items.extend(items)
                except Exception:
                    import traceback
                    print("[newsapi] request failed:")
                    traceback.print_exc()

        # NewsData
        # if args.provider in {"newsdata", "both"}:
        #     if not newsdata_key:
        #         print("[newsdata] NEWSDATA_API_KEY missing")
        #     else:
        #         try:
        #             items = await fetch_newsdata(client, newsdata_key, args.limit)
        #             all_items.extend(items)
        #         except Exception as exc:
        #             print(f"[newsdata] request failed: {exc}")

    if not all_items:
        print("No items returned.")
        return

    print(f"\nFetched {len(all_items)} headlines\n")

    for idx, item in enumerate(all_items, start=1):
        print(f"{idx}. [{item['provider']}] {item['title']}")
        print(f"   source: {item['source']}")
        print(f"   time:   {item['published']}")
        print(f"   url:    {item['url']}\n")


if __name__ == "__main__":
    asyncio.run(main())