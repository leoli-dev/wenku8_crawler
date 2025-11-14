#!/usr/bin/env python3
from __future__ import annotations

import sys
from html.parser import HTMLParser
from pathlib import Path
from typing import List


class ContentParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.in_content = False
        self.content_depth = 0
        self.skip_depth = 0
        self.chunks: List[str] = []

    def handle_starttag(self, tag: str, attrs_list) -> None:
        attrs = dict(attrs_list)
        if not self.in_content:
            if tag == "div" and attrs.get("id") == "content":
                self.in_content = True
                self.content_depth = 1
            return
        if tag == "div":
            self.content_depth += 1
        if tag in {"script", "style"}:
            self.skip_depth += 1
        elif tag == "ul" and attrs.get("id") == "contentdp":
            self.skip_depth += 1
        elif tag in {"br", "p", "li", "tr"} and self.skip_depth == 0:
            self.chunks.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if not self.in_content:
            return
        if tag in {"script", "style", "ul"} and self.skip_depth > 0:
            self.skip_depth -= 1
            return
        if tag == "div":
            self.content_depth -= 1
            if self.content_depth == 0:
                self.in_content = False
        elif tag in {"p", "li"} and self.skip_depth == 0:
            self.chunks.append("\n")

    def handle_data(self, data: str) -> None:
        if self.in_content and self.skip_depth == 0:
            self.chunks.append(data)

    def get_text(self) -> str:
        text = "".join(self.chunks)
        lines = [line.strip() for line in text.splitlines()]
        normalized: List[str] = []
        for line in lines:
            if not line:
                if normalized and normalized[-1] == "":
                    continue
                normalized.append("")
            else:
                normalized.append(line)
        return "\n".join(normalized).strip()


def extract_text(html_path: Path) -> str:
    parser = ContentParser()
    parser.feed(html_path.read_text(encoding="utf-8"))
    result = parser.get_text()
    if not result:
        raise RuntimeError("未能解析章节正文")
    return result


def main() -> None:
    if len(sys.argv) != 2:
        print("用法: extract_content.py <chapter.html>", file=sys.stderr)
        sys.exit(1)
    html_path = Path(sys.argv[1])
    print(extract_text(html_path))


if __name__ == "__main__":
    main()
