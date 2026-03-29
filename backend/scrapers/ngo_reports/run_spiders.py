from __future__ import annotations

import argparse

from scrapy.crawler import CrawlerProcess

from scrapers.ngo_reports import settings as ngo_settings
from scrapers.ngo_reports.spiders import (
    ActionAidIndiaReportsSpider,
    OxfamIndiaReportsSpider,
    PradanReportsSpider,
    SphereIndiaReportsSpider,
    SewaBharatReportsSpider,
)


def main() -> None:
    parser = argparse.ArgumentParser(description="Run NGO report spiders and export JSONL output.")
    parser.add_argument("--output", required=True, help="Path to JSONL output file")
    parser.add_argument("--max-pages", type=int, default=40, help="Max report links per spider")
    args = parser.parse_args()

    process_settings = {
        "BOT_NAME": ngo_settings.BOT_NAME,
        "SPIDER_MODULES": ngo_settings.SPIDER_MODULES,
        "NEWSPIDER_MODULE": ngo_settings.NEWSPIDER_MODULE,
        "ROBOTSTXT_OBEY": ngo_settings.ROBOTSTXT_OBEY,
        "DOWNLOAD_DELAY": ngo_settings.DOWNLOAD_DELAY,
        "CONCURRENT_REQUESTS": ngo_settings.CONCURRENT_REQUESTS,
        "USER_AGENT": ngo_settings.USER_AGENT,
        "RETRY_ENABLED": ngo_settings.RETRY_ENABLED,
        "RETRY_TIMES": ngo_settings.RETRY_TIMES,
        "TWISTED_REACTOR": ngo_settings.TWISTED_REACTOR,
        "PLAYWRIGHT_BROWSER_TYPE": ngo_settings.PLAYWRIGHT_BROWSER_TYPE,
        "PLAYWRIGHT_DEFAULT_NAVIGATION_TIMEOUT": ngo_settings.PLAYWRIGHT_DEFAULT_NAVIGATION_TIMEOUT,
        "PLAYWRIGHT_LAUNCH_OPTIONS": ngo_settings.PLAYWRIGHT_LAUNCH_OPTIONS,
        "DOWNLOAD_HANDLERS": ngo_settings.DOWNLOAD_HANDLERS,
        "FEEDS": {
            args.output: {
                "format": "jsonlines",
                "encoding": "utf8",
                "overwrite": False,
            }
        },
        "LOG_LEVEL": "INFO",
    }

    process = CrawlerProcess(process_settings)

    spiders = [
        OxfamIndiaReportsSpider,
        ActionAidIndiaReportsSpider,
        PradanReportsSpider,
        SphereIndiaReportsSpider,
        SewaBharatReportsSpider,
    ]
    for spider_cls in spiders:
        process.crawl(spider_cls, max_pages=args.max_pages)

    process.start()


if __name__ == "__main__":
    main()
