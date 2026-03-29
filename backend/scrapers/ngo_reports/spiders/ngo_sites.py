from __future__ import annotations

import re
from datetime import datetime, timezone
from urllib.parse import urljoin

import scrapy
from bs4 import BeautifulSoup

try:
    from newspaper import Article
except Exception:  # pragma: no cover - optional parser fallback
    Article = None

KEYWORDS = ["report", "publication", "research", "assessment", "brief", "study"]
REGION_TERMS = [
    "assam",
    "bihar",
    "jharkhand",
    "chhattisgarh",
    "bundelkhand",
    "marathwada",
    "maharashtra",
    "uttar pradesh",
    "madhya pradesh",
]
DATE_PATTERNS = [
    r"\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b",
    r"\b\d{4}-\d{2}-\d{2}\b",
    r"\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{1,2},?\s+\d{4}\b",
]


class BaseNGOReportsSpider(scrapy.Spider):
    custom_settings = {"LOG_LEVEL": "INFO"}
    source_org = "UNKNOWN"

    def __init__(self, max_pages: int = 40, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.max_pages = int(max_pages)
        self._seen_urls: set[str] = set()
        self._enqueued = 0

    def start_requests(self):
        for url in self.start_urls:
            yield scrapy.Request(
                url,
                callback=self.parse_listing,
                meta={"playwright": True},
                dont_filter=True,
            )

    def parse_listing(self, response: scrapy.http.Response):
        links = self._extract_candidate_links(response)
        for link in links:
            if self._enqueued >= self.max_pages:
                break
            if link in self._seen_urls:
                continue
            self._seen_urls.add(link)
            self._enqueued += 1

            if link.lower().endswith(".pdf"):
                yield self._build_item(response, link, is_pdf=True)
                continue

            yield scrapy.Request(
                link,
                callback=self.parse_report_page,
                meta={"playwright": True},
                dont_filter=True,
            )

    def parse_report_page(self, response: scrapy.http.Response):
        page_url = response.url
        pdf_url = self._extract_pdf_url(response)
        title = self._extract_title(response)
        text_blob = self._extract_text_blob(response)

        yield {
            "source_org": self.source_org,
            "source_url": page_url,
            "pdf_url": pdf_url,
            "title": title,
            "published_on": self._extract_date(text_blob),
            "region_tags": self._extract_regions(text_blob),
            "snippet": text_blob[:400],
            "raw_text": text_blob[:2000],
            "collected_at": datetime.now(timezone.utc).isoformat(),
        }

    def _build_item(self, response: scrapy.http.Response, link: str, is_pdf: bool = False):
        title = link.rsplit("/", 1)[-1].replace("-", " ").replace("_", " ")
        page_text = self._extract_text_blob(response)
        return {
            "source_org": self.source_org,
            "source_url": response.url,
            "pdf_url": link if is_pdf else "",
            "title": title[:180],
            "published_on": self._extract_date(page_text),
            "region_tags": self._extract_regions(page_text),
            "snippet": page_text[:400],
            "raw_text": page_text[:2000],
            "collected_at": datetime.now(timezone.utc).isoformat(),
        }

    def _extract_candidate_links(self, response: scrapy.http.Response) -> list[str]:
        hrefs = response.css("a::attr(href)").getall()
        soup = BeautifulSoup(response.text, "html.parser")
        hrefs.extend([a.get("href") for a in soup.select("a[href]")])

        links: list[str] = []
        for href in hrefs:
            if not href:
                continue
            abs_url = urljoin(response.url, href)
            low = abs_url.lower()
            if any(k in low for k in KEYWORDS) or low.endswith(".pdf"):
                links.append(abs_url)

        # Preserve order while de-duplicating.
        return list(dict.fromkeys(links))

    def _extract_pdf_url(self, response: scrapy.http.Response) -> str:
        candidate = response.css("a[href$='.pdf']::attr(href)").get()
        if candidate:
            return urljoin(response.url, candidate)

        soup = BeautifulSoup(response.text, "html.parser")
        anchor = soup.select_one("a[href$='.pdf']")
        if anchor and anchor.get("href"):
            return urljoin(response.url, anchor["href"])
        return ""

    def _extract_title(self, response: scrapy.http.Response) -> str:
        title = response.css("h1::text").get() or response.css("title::text").get() or ""
        return " ".join(title.split())[:180]

    def _extract_text_blob(self, response: scrapy.http.Response) -> str:
        soup = BeautifulSoup(response.text, "html.parser")
        html_text = " ".join(soup.stripped_strings)

        article_text = ""
        if Article is not None:
            try:
                article = Article(response.url)
                article.set_html(response.text)
                article.parse()
                article_text = (article.text or "").strip()
            except Exception:
                article_text = ""

        merged = article_text if len(article_text) > 200 else html_text
        return " ".join(merged.split())

    def _extract_regions(self, text: str) -> list[str]:
        lower = text.lower()
        return [region for region in REGION_TERMS if region in lower]

    def _extract_date(self, text: str) -> str:
        lower = text.lower()
        for pattern in DATE_PATTERNS:
            match = re.search(pattern, lower, re.IGNORECASE)
            if match:
                return match.group(0)
        return ""


class OxfamIndiaReportsSpider(BaseNGOReportsSpider):
    name = "oxfam_india_reports"
    source_org = "Oxfam India"
    start_urls = ["https://www.oxfamindia.org/research-publications"]


class ActionAidIndiaReportsSpider(BaseNGOReportsSpider):
    name = "actionaid_india_reports"
    source_org = "ActionAid India"
    start_urls = ["https://actionaidindia.org/our-work/reports"]


class PradanReportsSpider(BaseNGOReportsSpider):
    name = "pradan_reports"
    source_org = "PRADAN"
    start_urls = ["https://pradan.net/publications"]


class SphereIndiaReportsSpider(BaseNGOReportsSpider):
    name = "sphere_india_reports"
    source_org = "Sphere India"
    start_urls = ["https://sphereindia.org.in/reports"]


class SewaBharatReportsSpider(BaseNGOReportsSpider):
    name = "sewa_bharat_reports"
    source_org = "SEWA Bharat"
    start_urls = ["https://sewabharat.org/research"]
