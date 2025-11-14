#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from collections import OrderedDict
from html.parser import HTMLParser
from pathlib import Path
from typing import List, Tuple
from urllib.parse import urljoin


Chapter = Tuple[str, str]


def sanitize(text: str) -> str:
    cleaned = re.sub(r"\s+", " ", text).strip()
    cleaned = re.sub(r"[^\w-]+", "_", cleaned, flags=re.UNICODE)
    cleaned = re.sub(r"_+", "_", cleaned)
    return cleaned.strip("_") or "untitled"


class CatalogParser(HTMLParser):
    def __init__(self, base_url: str) -> None:
        super().__init__()
        self.base_url = base_url
        self.title_chunks: List[str] = []
        self.in_title = False
        self.capture_table = False
        self.current_td_class: str | None = None
        self.in_volume_header = False
        self.volume_chunks: List[str] = []
        self.current_volume: str | None = None
        self.current_link: str | None = None
        self.current_link_text: List[str] = []
        self.volumes: "OrderedDict[str, List[Chapter]]" = OrderedDict()

    def handle_starttag(self, tag: str, attrs_list) -> None:
        attrs = dict(attrs_list)
        if tag == "div" and attrs.get("id") == "title":
            self.in_title = True
            return
        if tag == "table" and attrs.get("class") == "css":
            self.capture_table = True
            return
        if not self.capture_table:
            return
        if tag == "td":
            self.current_td_class = attrs.get("class")
            if self.current_td_class == "vcss":
                self.in_volume_header = True
                self.volume_chunks = []
            return
        if tag == "a" and self.current_td_class == "ccss":
            href = attrs.get("href")
            if href:
                self.current_link = urljoin(self.base_url, href)
                self.current_link_text = []

    def handle_endtag(self, tag: str) -> None:
        if tag == "div" and self.in_title:
            self.in_title = False
            return
        if tag == "table" and self.capture_table:
            self.capture_table = False
            return
        if not self.capture_table:
            return
        if tag == "td":
            if self.in_volume_header:
                volume_name = "".join(self.volume_chunks).strip()
                if volume_name:
                    self.current_volume = volume_name
                    self.volumes.setdefault(volume_name, [])
                self.in_volume_header = False
            self.current_td_class = None
            return
        if tag == "a" and self.current_link:
            chapter_title = "".join(self.current_link_text).strip()
            if chapter_title and "插图" not in chapter_title:
                if not self.current_volume:
                    self.current_volume = "未分卷"
                    self.volumes.setdefault(self.current_volume, [])
                self.volumes[self.current_volume].append((chapter_title, self.current_link))
            self.current_link = None
            self.current_link_text = []

    def handle_data(self, data: str) -> None:
        if self.in_title:
            self.title_chunks.append(data)
            return
        if not self.capture_table:
            return
        if self.in_volume_header:
            self.volume_chunks.append(data)
        elif self.current_link:
            self.current_link_text.append(data)


def parse_catalog(html_path: Path, base_url: str) -> tuple[str, str, OrderedDict[str, List[Chapter]]]:
    parser = CatalogParser(base_url)
    parser.feed(html_path.read_text(encoding="utf-8"))
    raw_title = "".join(parser.title_chunks).strip()
    safe_title = sanitize(raw_title)
    if not raw_title:
        raise RuntimeError("无法读取目录标题")
    return raw_title, safe_title, parser.volumes


def main() -> None:
    if len(sys.argv) != 3:
        print("用法: parse_catalog.py <catalog.html> <catalog_url>", file=sys.stderr)
        sys.exit(1)
    html_path = Path(sys.argv[1])
    catalog_url = sys.argv[2]
    raw_title, safe_title, volumes = parse_catalog(html_path, catalog_url)
    print("\t".join(["TITLE", raw_title, safe_title]))
    for volume_name, chapters in volumes.items():
        if not chapters:
            continue
        volume_safe = sanitize(volume_name)
        print("\t".join(["VOLUME", volume_name, volume_safe]))
        for chapter_title, chapter_url in chapters:
            chapter_safe = sanitize(chapter_title)
            print("\t".join(["CHAPTER", volume_safe, chapter_title, chapter_safe, chapter_url]))


if __name__ == "__main__":
    main()
