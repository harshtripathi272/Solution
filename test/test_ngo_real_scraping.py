import sys
from pathlib import Path
import pytest
import os
import json
from scrapy.crawler import CrawlerProcess
from scrapy.utils.project import get_project_settings

# Add backend to import path
sys.path.append(str(Path(__file__).resolve().parents[1] / "backend"))

from scrapers.ngo_reports.spiders import (
    OxfamIndiaReportsSpider,
    ActionAidIndiaReportsSpider,
    PradanReportsSpider,
    SphereIndiaReportsSpider,
    SewaBharatReportsSpider,
    NFIReportsSpider,
    VHAIReportsSpider,
)

# REAL-WORLD INTEGRATION TEST (SMOKE TEST)
@pytest.fixture
def run_spider_to_file(tmp_path):
    """Fixture to run a spider and return the collected items."""
    def _run(spider_cls):
        output_file = tmp_path / "output.jsonl"
        
        # Scrapy settings for the test run
        settings = {
            "FEEDS": {
                str(output_file): {
                    "format": "jsonlines",
                    "encoding": "utf8",
                    "overwrite": True,
                }
            },
            "LOG_LEVEL": "INFO",
            "USER_AGENT": "SevaSetuTestBot/0.1",
            "DOWNLOAD_DELAY": 1,
            # Playwright might be needed for some JS-heavy sites
            "TWISTED_REACTOR": "twisted.internet.asyncioreactor.AsyncioSelectorReactor",
            "DOWNLOAD_HANDLERS": {
                "http": "scrapy_playwright.handler.ScrapyPlaywrightDownloadHandler",
                "https": "scrapy_playwright.handler.ScrapyPlaywrightDownloadHandler",
            },
            "PLAYWRIGHT_BROWSER_TYPE": "chromium",
            "PLAYWRIGHT_LAUNCH_OPTIONS": {"headless": True},
            "PLAYWRIGHT_DEFAULT_NAVIGATION_TIMEOUT": 60000,
        }
        
        process = CrawlerProcess(settings)
        process.crawl(spider_cls, max_pages=10) # Enough to catch all links on listing pages
        process.start()
        
        items = []
        if output_file.exists():
            with open(output_file, "r", encoding="utf-8") as f:
                for line in f:
                    items.append(json.loads(line))
        return items
    return _run


@pytest.mark.parametrize("spider_cls", [
    # OxfamIndiaReportsSpider,
    # ActionAidIndiaReportsSpider,
    PradanReportsSpider,
    # SphereIndiaReportsSpider,
    # SewaBharatReportsSpider,
    #NFIReportsSpider,
    #VHAIReportsSpider,
])
def test_ngo_spider_real_connectivity(spider_cls, run_spider_to_file): 
    """
    Smoke test to verify that the spider can connect to the target URL
    and extract all valid items.
    """
    items = run_spider_to_file(spider_cls)
    
    assert len(items) > 0, f"Spider {spider_cls.name} collected no items from {spider_cls.start_urls}"
    
    print(f"\n[DEBUG] Collected {len(items)} items from {spider_cls.name}:")
    for idx, item in enumerate(items, 1):
        print(f"\n--- Item {idx} ---")
        print(json.dumps(item, indent=2))
    
    for item in items:
        assert "source_org" in item
        assert "source_url" in item
        assert "title" in item
        assert len(item["title"]) > 0
        assert item["collected_at"] is not None
