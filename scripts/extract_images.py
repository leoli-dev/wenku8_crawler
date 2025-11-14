#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from typing import List
from urllib.parse import urljoin, urlparse


def sanitize_filename(name: str, index: int) -> str:
    base = name or f"image_{index}.jpg"
    base = base.split("?")[0]
    cleaned = re.sub(r"[^\w.-]+", "_", base, flags=re.UNICODE)
    cleaned = cleaned.strip("._")
    if not cleaned:
        cleaned = f"image_{index}.jpg"
    return cleaned


class ImageExtractor(HTMLParser):
    def __init__(self, base_url: str) -> None:
        super().__init__()
        self.base_url = base_url
        self.in_content = False
        self.content_depth = 0
        self.images: List[str] = []

    def handle_starttag(self, tag: str, attrs_list) -> None:
        attrs = dict(attrs_list)
        if not self.in_content:
            if tag == "div" and attrs.get("id") == "content":
                self.in_content = True
                self.content_depth = 1
            return
        if tag == "div":
            self.content_depth += 1
        if tag == "img":
            src = attrs.get("src")
            if src:
                full_url = urljoin(self.base_url, src)
                self.images.append(full_url)

    def handle_endtag(self, tag: str) -> None:
        if not self.in_content:
            return
        if tag == "div":
            self.content_depth -= 1
            if self.content_depth == 0:
                self.in_content = False


def extract_images(html_path: Path, base_url: str) -> List[str]:
    parser = ImageExtractor(base_url)
    parser.feed(html_path.read_text(encoding="utf-8"))
    return parser.images


def main() -> None:
    if len(sys.argv) != 3:
        print("用法: extract_images.py <chapter.html> <chapter_url>", file=sys.stderr)
        sys.exit(1)
    html_path = Path(sys.argv[1])
    chapter_url = sys.argv[2]
    images = extract_images(html_path, chapter_url)
    for idx, image_url in enumerate(images, start=1):
        parsed = urlparse(image_url)
        name = Path(parsed.path).name
        safe_name = sanitize_filename(name, idx)
        print(f"{image_url}\t{safe_name}")


if __name__ == "__main__":
    main()
