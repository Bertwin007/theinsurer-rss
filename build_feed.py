"""Build feed.xml from The Insurer's public sitemap.

Reads only the sitemap linked from robots.txt. Does not open article pages.
"""

import os
import re
from datetime import datetime
from email.utils import format_datetime
from pathlib import Path
from urllib.request import Request, urlopen
from xml.etree import ElementTree as ET

INDEX_URL = (
    "https://www.theinsurer.com/arc/outboundfeeds/"
    "sitemap-index-insurer/?outputType=xml"
)
SITEMAP_NS = "http://www.sitemaps.org/schemas/sitemap/0.9"
MAX_ITEMS = 50
OUT_PATH = Path(__file__).with_name("feed.xml")

SECTIONS = {
    "ti": "The Insurer",
    "tv": "The Insurer TV",
    "sustainable-insurance": "Sustainable Insurer",
    "program-manager": "Program Manager",
    "cyber-risk": "Cyber Risk",
    "parametric-insurer": "Parametric Insurer",
    "e-and-s": "E&S Insurer",
}


def fetch_xml(url: str) -> ET.Element:
    request = Request(url, headers={"User-Agent": "theinsurer-sitemap-feed/1.0"})
    with urlopen(request, timeout=40) as response:
        return ET.fromstring(response.read())


def title_from_url(url: str) -> str:
    slug = url.rstrip("/").rsplit("/", 1)[-1]
    slug = re.sub(r"-\d{4}-\d{2}-\d{2}$", "", slug)
    words = slug.replace("-", " ").strip()
    return words[:1].upper() + words[1:] if words else url


def section_from_url(url: str) -> str:
    path = url.split("://", 1)[-1].split("/", 1)[-1]
    key = path.split("/", 1)[0]
    return SECTIONS.get(key, "The Insurer")


def local(tag: str) -> str:
    return f"{{{SITEMAP_NS}}}{tag}"


def main() -> None:
    index = fetch_xml(INDEX_URL)
    first_sitemap = index.find(f"{local('sitemap')}/{local('loc')}").text
    sitemap = fetch_xml(first_sitemap)

    items = []
    for node in sitemap.findall(local("url")):
        link = node.find(local("loc")).text
        updated = datetime.fromisoformat(node.find(local("lastmod")).text.replace("Z", "+00:00"))
        items.append(
            {
                "link": link,
                "updated": updated,
                "title": title_from_url(link),
                "section": section_from_url(link),
            }
        )

    items.sort(key=lambda item: item["updated"], reverse=True)
    items = items[:MAX_ITEMS]
    if not items:
        raise SystemExit("Sitemap contained no articles")

    public_url = os.environ.get("FEED_PUBLIC_URL", "").strip()
    rss = ET.Element("rss", {"version": "2.0"})
    rss.set("xmlns:atom", "http://www.w3.org/2005/Atom")
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "The Insurer"
    ET.SubElement(channel, "link").text = "https://www.theinsurer.com/"
    ET.SubElement(channel, "description").text = (
        "Latest articles from theinsurer.com, built from the public sitemap. "
        "Titles are taken from the article URL."
    )
    ET.SubElement(channel, "language").text = "en"
    ET.SubElement(channel, "lastBuildDate").text = format_datetime(items[0]["updated"])
    if public_url:
        atom_link = ET.SubElement(channel, "{http://www.w3.org/2005/Atom}link")
        atom_link.set("href", public_url)
        atom_link.set("rel", "self")
        atom_link.set("type", "application/rss+xml")

    for item in items:
        entry = ET.SubElement(channel, "item")
        ET.SubElement(entry, "title").text = item["title"]
        ET.SubElement(entry, "link").text = item["link"]
        guid = ET.SubElement(entry, "guid")
        guid.set("isPermaLink", "true")
        guid.text = item["link"]
        ET.SubElement(entry, "pubDate").text = format_datetime(item["updated"])
        ET.SubElement(entry, "category").text = item["section"]
        ET.SubElement(entry, "description").text = (
            f"{item['section']} — {item['updated'].strftime('%Y-%m-%d')}"
        )

    tree = ET.ElementTree(rss)
    ET.indent(tree, space="  ")
    tree.write(OUT_PATH, encoding="utf-8", xml_declaration=True)
    print(f"Wrote {len(items)} items to {OUT_PATH}")


if __name__ == "__main__":
    main()
