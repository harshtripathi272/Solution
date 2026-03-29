import os

BOT_NAME = "ngo_reports"
SPIDER_MODULES = ["scrapers.ngo_reports.spiders"]
NEWSPIDER_MODULE = "scrapers.ngo_reports.spiders"

ROBOTSTXT_OBEY = True
DOWNLOAD_DELAY = 2
CONCURRENT_REQUESTS = int(os.getenv("NGO_SCRAPY_CONCURRENCY", "4"))
USER_AGENT = os.getenv(
    "NGO_SCRAPY_USER_AGENT",
    "SevaSetuCommunityIntelBot/0.1 (+prototype; contact: hello@sevasetu.local)",
)

# Keep retries conservative to avoid hammering source websites.
RETRY_ENABLED = True
RETRY_TIMES = 2
REQUEST_FINGERPRINTER_IMPLEMENTATION = "2.7"

TWISTED_REACTOR = "twisted.internet.asyncioreactor.AsyncioSelectorReactor"

PLAYWRIGHT_BROWSER_TYPE = "chromium"
PLAYWRIGHT_DEFAULT_NAVIGATION_TIMEOUT = 30_000
PLAYWRIGHT_LAUNCH_OPTIONS = {
    "headless": True,
}
PLAYWRIGHT_CONTEXTS = {
    "default": {
        "ignore_https_errors": True,
    }
}

DOWNLOAD_HANDLERS = {
    "http": "scrapy_playwright.handler.ScrapyPlaywrightDownloadHandler",
    "https": "scrapy_playwright.handler.ScrapyPlaywrightDownloadHandler",
}
