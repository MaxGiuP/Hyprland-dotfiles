#!/usr/bin/env python3

from __future__ import annotations

from html import escape
from urllib.parse import urljoin, urlparse, quote_plus
from urllib.request import Request, urlopen
import re
import sys

from bs4 import BeautifulSoup, NavigableString, Tag
from readability import Document


BLOCK_TAGS = {
    "article",
    "aside",
    "blockquote",
    "div",
    "figcaption",
    "figure",
    "footer",
    "header",
    "li",
    "main",
    "nav",
    "ol",
    "p",
    "pre",
    "section",
    "table",
    "tbody",
    "thead",
    "tr",
    "td",
    "th",
    "ul",
}

DROP_TAGS = {
    "audio",
    "button",
    "canvas",
    "dialog",
    "embed",
    "form",
    "iframe",
    "img",
    "input",
    "link",
    "meta",
    "noscript",
    "object",
    "picture",
    "script",
    "select",
    "source",
    "style",
    "svg",
    "textarea",
    "video",
}

MAX_OUTPUT_CHARS = 120_000
MAX_NODES = 600


def normalize_space(text: str) -> str:
    return re.sub(r"\s+", " ", text or "").strip()


def parse_html(url: str) -> tuple[str, str]:
    req = Request(
        url,
        headers={
            "User-Agent": (
                "Mozilla/5.0 (X11; Linux x86_64) "
                "AppleWebKit/537.36 Chrome/122 Safari/537.36"
            )
        },
    )

    with urlopen(req, timeout=15) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        raw = response.read().decode(charset, errors="replace")

    return raw, charset


def clean_tree(root: BeautifulSoup | Tag) -> None:
    for tag in root.find_all(DROP_TAGS):
        tag.decompose()

    for tag in root.find_all(True):
        attrs = dict(tag.attrs)
        kept = {}
        if "href" in attrs:
            kept["href"] = attrs["href"]
        if "colspan" in attrs:
            kept["colspan"] = attrs["colspan"]
        if "rowspan" in attrs:
            kept["rowspan"] = attrs["rowspan"]
        tag.attrs = kept


def is_search_url(url: str) -> bool:
    parsed = urlparse(url)
    host = parsed.netloc.lower()
    return (
        "duckduckgo.com" in host
        or "google." in host
        or "bing.com" in host
    )


def select_search_root(soup: BeautifulSoup) -> Tag | None:
    selectors = [
        ".results",
        "#links",
        "#b_content",
        "main",
        "[role='main']",
        "body",
    ]
    for selector in selectors:
        node = soup.select_one(selector)
        if node:
            return node
    return None


def render_search_results(soup: BeautifulSoup, url: str, title: str) -> str | None:
    root = select_search_root(soup)
    if root is None:
        return None

    entries = []
    selectors = [
        ".result",
        ".web-result",
        ".result.results_links",
        ".b_algo",
        ".fdb",
    ]
    for selector in selectors:
        matches = root.select(selector)
        if len(matches) >= 2:
            entries = matches
            break

    if not entries:
        return None

    blocks = [
        f"<h2>{escape(title)}</h2>",
        f"<p><a href=\"{escape(url, quote=True)}\">{escape(url)}</a></p>",
    ]

    seen = set()
    for entry in entries[:15]:
        link = entry.find("a", href=True)
        if not link:
            continue

        href = urljoin(url, normalize_space(link["href"]))
        label = normalize_space(link.get_text(" ", strip=True))
        snippet_node = entry.select_one(".result__snippet, .b_caption p, .snippet, .excerpt")
        snippet = normalize_space(snippet_node.get_text(" ", strip=True)) if snippet_node else ""
        key = (label, href)
        if not label or key in seen:
            continue
        seen.add(key)

        blocks.append(f"<h3><a href=\"{escape(href, quote=True)}\">{escape(label)}</a></h3>")
        blocks.append(f"<p>{escape(href)}</p>")
        if snippet:
            blocks.append(f"<p>{escape(snippet)}</p>")

    return "\n".join(blocks) if len(blocks) > 2 else None


def choose_content_root(raw_html: str, soup: BeautifulSoup, url: str) -> Tag:
    if is_search_url(url):
        search_root = select_search_root(soup)
        if search_root is not None:
            return search_root

    selectors = [
        "main",
        "article",
        "[role='main']",
        "#content",
        ".content",
        "body",
    ]
    for selector in selectors:
        node = soup.select_one(selector)
        if node and normalize_space(node.get_text(" ", strip=True)):
            return node

    try:
        summary = Document(raw_html).summary(html_partial=True)
        article = BeautifulSoup(summary, "html.parser")
        clean_tree(article)
        if normalize_space(article.get_text(" ", strip=True)):
            wrapper = soup.new_tag("div")
            for child in list(article.contents):
                wrapper.append(child)
            return wrapper
    except Exception:
        pass

    return soup


def inline_text(node: Tag | NavigableString, base_url: str) -> str:
    if isinstance(node, NavigableString):
        text = str(node)
        if not text.strip():
            return " "
        return escape(text)

    if not isinstance(node, Tag):
        return ""

    name = node.name.lower()
    if name == "br":
        return "<br/>"

    body = "".join(inline_text(child, base_url) for child in node.children).strip()
    if not body and name not in {"hr"}:
        return ""

    if name == "a":
        href = normalize_space(node.get("href", ""))
        if not href:
            return body
        resolved = urljoin(base_url, href)
        return f"<a href=\"{escape(resolved, quote=True)}\">{body or escape(resolved)}</a>"
    if name in {"strong", "b"}:
        return f"<b>{body}</b>"
    if name in {"em", "i"}:
        return f"<i>{body}</i>"
    if name == "code":
        return f"<tt>{body}</tt>"
    if name in {"span", "small", "mark", "sup", "sub", "time", "label"}:
        return body
    if name == "hr":
        return "<p>--------------------------------</p>"

    return body


def collect_blocks(node: Tag, base_url: str, blocks: list[str], depth: int = 0) -> None:
    if len(blocks) >= MAX_NODES:
        return

    for child in node.children:
        if len(blocks) >= MAX_NODES:
            return

        if isinstance(child, NavigableString):
            continue
        if not isinstance(child, Tag):
            continue

        name = child.name.lower()
        if name in DROP_TAGS:
            continue

        if name in {"h1", "h2", "h3", "h4"}:
            text = normalize_space(child.get_text(" ", strip=True))
            if text:
                level = {"h1": "h2", "h2": "h3", "h3": "h4", "h4": "h4"}[name]
                blocks.append(f"<{level}>{escape(text)}</{level}>")
            continue

        if name == "p":
            body = inline_text(child, base_url).strip()
            if normalize_space(child.get_text(" ", strip=True)):
                blocks.append(f"<p>{body}</p>")
            continue

        if name in {"ul", "ol"}:
            items = []
            for li in child.find_all("li", recursive=False):
                item = inline_text(li, base_url).strip()
                if normalize_space(li.get_text(" ", strip=True)):
                    items.append(f"<li>{item}</li>")
            if items:
                tag_name = "ol" if name == "ol" else "ul"
                blocks.append(f"<{tag_name}>{''.join(items)}</{tag_name}>")
            continue

        if name == "blockquote":
            inner = []
            collect_blocks(child, base_url, inner, depth + 1)
            if inner:
                blocks.append(f"<blockquote>{''.join(inner[:10])}</blockquote>")
            else:
                text = normalize_space(child.get_text(" ", strip=True))
                if text:
                    blocks.append(f"<blockquote><p>{escape(text)}</p></blockquote>")
            continue

        if name == "pre":
            text = child.get_text("\n", strip=False).strip("\n")
            if text.strip():
                blocks.append(f"<pre>{escape(text)}</pre>")
            continue

        if name == "table":
            rows = []
            for tr in child.find_all("tr", recursive=False):
                cells = []
                for cell in tr.find_all(["th", "td"], recursive=False):
                    tag_name = "th" if cell.name.lower() == "th" else "td"
                    body = inline_text(cell, base_url).strip()
                    if body:
                        cells.append(f"<{tag_name}>{body}</{tag_name}>")
                if cells:
                    rows.append(f"<tr>{''.join(cells)}</tr>")
            if rows:
                blocks.append(f"<table>{''.join(rows[:20])}</table>")
            continue

        if name == "a":
            body = inline_text(child, base_url).strip()
            if body:
                blocks.append(f"<p>{body}</p>")
            continue

        if name in BLOCK_TAGS:
            collect_blocks(child, base_url, blocks, depth + 1)
            continue

        body = inline_text(child, base_url).strip()
        if body and normalize_space(child.get_text(" ", strip=True)):
            blocks.append(f"<p>{body}</p>")


def render_document(url: str, raw_html: str) -> str:
    soup = BeautifulSoup(raw_html, "html.parser")
    clean_tree(soup)

    title = normalize_space(soup.title.get_text(" ", strip=True) if soup.title else "") or url

    if is_search_url(url):
        search_render = render_search_results(soup, url, title)
        if search_render:
            return search_render[:MAX_OUTPUT_CHARS]

    root = choose_content_root(raw_html, soup, url)
    blocks = [
        f"<h2>{escape(title)}</h2>",
        f"<p><a href=\"{escape(url, quote=True)}\">{escape(url)}</a></p>",
    ]
    collect_blocks(root, url, blocks)

    if len(blocks) <= 2:
        text = normalize_space(root.get_text("\n", strip=True))
        if text:
            for paragraph in text.split("\n"):
                paragraph = normalize_space(paragraph)
                if paragraph:
                    blocks.append(f"<p>{escape(paragraph)}</p>")

    return "\n".join(blocks)[:MAX_OUTPUT_CHARS]


def normalize_url(value: str) -> str:
    text = normalize_space(value)
    if not text:
        return "https://duckduckgo.com/html/?q=web"
    if re.match(r"^[a-zA-Z][a-zA-Z0-9+.-]*:", text):
        return text
    if " " in text or "." not in text:
        return f"https://duckduckgo.com/html/?q={quote_plus(text)}"
    return f"https://{text}"


def main() -> None:
    if len(sys.argv) < 2:
        raise SystemExit("usage: fetch_page.py URL")

    url = normalize_url(sys.argv[1])
    raw_html, _ = parse_html(url)
    print(render_document(url, raw_html))


if __name__ == "__main__":
    main()
