import pytest
from scrapy.http import HtmlResponse, Request
from scrapers.ngo_reports.spiders.ngo_sites import (
    BaseNGOReportsSpider,
    OxfamIndiaReportsSpider,
    ActionAidIndiaReportsSpider,
    PradanReportsSpider,
    SphereIndiaReportsSpider,
    SewaBharatReportsSpider,
    NFIReportsSpider,
    VHAIReportsSpider,
)

# ---------------------------------------------------------------------------
# Mock Response Helper
# ---------------------------------------------------------------------------
def fake_response_from_str(html_content: str, url: str) -> HtmlResponse:
    request = Request(url=url)
    return HtmlResponse(url=url, request=request, body=html_content, encoding="utf-8")

# ---------------------------------------------------------------------------
# Unit Tests for Parsing Logic
# ---------------------------------------------------------------------------

@pytest.fixture
def base_spider():
    return BaseNGOReportsSpider()

def test_extract_candidate_links(base_spider):
    html = """
    <html>
        <body>
            <a href="/report1.pdf">PDF Report</a>
            <a href="https://example.com/publication/study-2024">Research Study</a>
            <a href="/about-us">About</a>
        </body>
    </html>
    """
    response = fake_response_from_str(html, "https://ngo.org/listing")
    links = base_spider._extract_candidate_links(response)
    
    # Base spider filters for "report", "publication", "research", etc.
    assert "https://ngo.org/report1.pdf" in links
    assert "https://example.com/publication/study-2024" in links
    assert "https://ngo.org/about-us" not in links

def test_extract_regions(base_spider):
    text = "This report covers the impact of flood in Bihar and parts of Jharkhand."
    regions = base_spider._extract_regions(text)
    assert "bihar" in regions
    assert "jharkhand" in regions
    assert "assam" not in regions

def test_extract_title(base_spider):
    html = "<html><head><title>Annual Report 2024</title></head><body><h1>Crisis Impact Study</h1></body></html>"
    response = fake_response_from_str(html, "https://ngo.org/res")
    title = base_spider._extract_title(response)
    # Prefers h1 over title
    assert title == "Crisis Impact Study"

def test_parse_report_page(base_spider):
    html = """
    <html>
        <body>
            <h1>Flood Relief in Assam</h1>
            <p>Published on Jan 15, 2025. This study evaluates the community needs in Assam.</p>
            <a href="/download/full-report.pdf">Download PDF</a>
        </body>
    </html>
    """
    response = fake_response_from_str(html, "https://ngo.org/report/assam-flood")
    items = list(base_spider.parse_report_page(response))
    
    assert len(items) == 1
    item = items[0]
    assert item["source_org"] == "UNKNOWN"
    assert "Assam" in item["title"]
    assert "assam" in item["region_tags"]
    assert "2025" in item["published_on"]
    assert "full-report.pdf" in item["pdf_url"]

# ---------------------------------------------------------------------------
# Smoke Test for Spider Configurations
# ---------------------------------------------------------------------------

def test_spider_start_urls():
    spiders = [
        OxfamIndiaReportsSpider(),
        ActionAidIndiaReportsSpider(),
        PradanReportsSpider(),
        SphereIndiaReportsSpider(),
        SewaBharatReportsSpider(),
        NFIReportsSpider(),
        VHAIReportsSpider(),
    ]
    
    for spider in spiders:
        assert len(spider.start_urls) > 0
        assert spider.source_org != "UNKNOWN"
        assert spider.name is not None
        # Verify no 404-prone mock URLs are left (heuristic check)
        for url in spider.start_urls:
            assert "mock" not in url.lower()
            assert "example.com" not in url.lower()
