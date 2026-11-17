#!/usr/bin/env python3
"""Turns INSTALL.md into the printable "Start Here" page that ships inside the installer.

    python3 scripts/install_guide_html.py INSTALL.md guide.html

Handles the small subset of Markdown INSTALL.md uses: headings, paragraphs, numbered and bulleted
lists, tables, **bold**, *italic*, `code`, [links](url), inline HTML such as <kbd>, GitHub alert
boxes (> [!NOTE] / [!TIP] / [!WARNING]) and <!-- pagebreak --> comments. make_installer.sh prints
the result to PDF with a Chromium-based browser.
"""
import html
import re
import sys

CSS = """
@page { size: Letter; margin: 0.7in 0.75in; }
:root { --ink:#1d2a44; --amber:#e39b2d; --soft:#f7f1e6; --muted:#5b6478; --line:#e6dccb; }
* { box-sizing: border-box; }
body { font-family: -apple-system, "SF Pro Text", "Helvetica Neue", Arial, sans-serif; color: var(--ink);
       font-size: 12pt; line-height: 1.45; margin: 0; background: #fff; }
a { color: var(--ink); }
h1 { font-family: ui-rounded, -apple-system, sans-serif; font-size: 28pt; margin: 0 0 4pt; }
.eyebrow { color: var(--amber); font-weight: 700; letter-spacing: .02em; font-size: 11pt; }
.lead { font-size: 14pt; color: var(--muted); margin: 0 0 14pt; }
h2 { font-family: ui-rounded, -apple-system, sans-serif; font-size: 18pt; margin: 22pt 0 6pt;
     display: flex; align-items: center; gap: 10pt; break-after: avoid; }
h2 .n { display: inline-flex; width: 28pt; height: 28pt; border-radius: 50%; background: var(--amber); color: #fff;
        align-items: center; justify-content: center; font-size: 14pt; flex: none; }
h3 { font-size: 14pt; margin: 14pt 0 4pt; break-after: avoid; }
ol, ul { padding-left: 22pt; margin: 4pt 0 8pt; }
li { margin: 4pt 0; }
b, strong { font-weight: 650; }
.box { background: var(--soft); border: 1px solid var(--line); border-radius: 10pt; padding: 10pt 14pt;
       margin: 10pt 0; break-inside: avoid; }
.box.warning { border-left: 5pt solid var(--amber); }
.box p { margin: 4pt 0; }
code { font-family: ui-monospace, Menlo, monospace; font-size: 11pt; }
kbd { display: inline-block; border: 1px solid #b9b2a4; border-bottom-width: 2px; border-radius: 4pt;
      padding: 0 5pt; font: 11pt -apple-system, sans-serif; background: #fff; }
table { border-collapse: collapse; width: 100%; margin: 6pt 0; font-size: 11.5pt; }
tr { break-inside: avoid; }
th { text-align: left; padding: 6pt 8pt; color: var(--muted); font-weight: 600; }
td { border-top: 1px solid var(--line); padding: 6pt 8pt; vertical-align: top; }
td:first-child { width: 42%; font-weight: 600; }
.pagebreak { break-before: page; }
"""


def inline(text):
    """Escapes text but keeps the inline HTML tags INSTALL.md uses, then applies inline Markdown."""
    allowed = re.compile(r"</?(kbd|b|i|em|strong|br)\s*/?>")
    kept = []

    def keep(match):
        kept.append(match.group(0))
        return f"\x00{len(kept) - 1}\x00"

    text = allowed.sub(keep, text)
    codes = []

    def code(match):
        codes.append(f"<code>{html.escape(match.group(1))}</code>")
        return f"\x01{len(codes) - 1}\x01"

    text = re.sub(r"`([^`]+)`", code, text)
    text = html.escape(text, quote=False)
    text = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", lambda m: f'<a href="{html.escape(m.group(2))}">{m.group(1)}</a>', text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"(?<![*\w])\*(?!\s)(.+?)(?<!\s)\*(?![*\w])", r"<i>\1</i>", text)
    text = re.sub(r"\x01(\d+)\x01", lambda m: codes[int(m.group(1))], text)
    return re.sub(r"\x00(\d+)\x00", lambda m: kept[int(m.group(1))], text)


def render(lines):
    out = []
    i = 0
    pagebreak = False

    def take_pagebreak():
        nonlocal pagebreak
        cls = ' class="pagebreak"' if pagebreak else ""
        pagebreak = False
        return cls

    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if not stripped:
            i += 1
            continue
        if stripped == "<!-- pagebreak -->":
            pagebreak = True
            i += 1
            continue
        if stripped.startswith("<!--"):
            i += 1
            continue
        heading = re.match(r"^(#{1,3}) (.*)$", stripped)
        if heading:
            level, text = len(heading.group(1)), heading.group(2)
            if level == 1:
                out.append('<div class="eyebrow">✦ START HERE</div>')
                out.append(f"<h1>{inline(text)}</h1>")
                # The paragraph right after the title is the lead.
                i += 1
                para = []
                while i < len(lines) and not lines[i].strip():
                    i += 1
                while i < len(lines) and lines[i].strip() and not re.match(r"^(#|>|\||- |\d+\. |<!--)", lines[i].strip()):
                    para.append(lines[i].strip())
                    i += 1
                if para:
                    out.append(f'<p class="lead">{inline(" ".join(para))}</p>')
                continue
            if level == 2:
                numbered = re.match(r"^(\d+)\. (.*)$", text)
                badge = f'<span class="n">{numbered.group(1)}</span> ' if numbered else ""
                title = numbered.group(2) if numbered else text
                out.append(f"<h2{take_pagebreak()}>{badge}{inline(title)}</h2>")
            else:
                out.append(f"<h3{take_pagebreak()}>{inline(text)}</h3>")
            i += 1
            continue
        if stripped.startswith(">"):
            block = []
            while i < len(lines) and lines[i].strip().startswith(">"):
                block.append(re.sub(r"^\s*> ?", "", lines[i]))
                i += 1
            kind = "note"
            alert = re.match(r"^\[!(NOTE|TIP|WARNING|IMPORTANT|CAUTION)\]\s*$", block[0].strip()) if block else None
            if alert:
                kind = alert.group(1).lower()
                block = block[1:]
            cls = "box warning" if kind in ("warning", "caution", "important") else "box"
            out.append(f'<div class="{cls}"{take_pagebreak()}>{render(block)}</div>')
            continue
        if stripped.startswith("|"):
            rows = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                cells = [c.strip() for c in lines[i].strip().strip("|").split("|")]
                if not all(re.fullmatch(r":?-{3,}:?", c) for c in cells):
                    rows.append(cells)
                i += 1
            table = [f"<table{take_pagebreak()}>"]
            if rows:
                table.append("<tr>" + "".join(f"<th>{inline(c)}</th>" for c in rows[0]) + "</tr>")
                for row in rows[1:]:
                    table.append("<tr>" + "".join(f"<td>{inline(c)}</td>" for c in row) + "</tr>")
            table.append("</table>")
            out.append("\n".join(table))
            continue
        list_item = re.match(r"^(- |\d+\. )", stripped)
        if list_item:
            tag = "ul" if stripped.startswith("- ") else "ol"
            items = []
            while i < len(lines):
                s = lines[i].strip()
                m = re.match(r"^(- |\d+\. )(.*)$", s)
                if m and (("ul" if s.startswith("- ") else "ol") == tag):
                    items.append(m.group(2))
                elif s and items and lines[i].startswith((" ", "\t")):
                    items[-1] += " " + s          # wrapped continuation line
                else:
                    break
                i += 1
            out.append(f"<{tag}{take_pagebreak()}>" + "".join(f"<li>{inline(t)}</li>" for t in items) + f"</{tag}>")
            continue
        para = []
        while i < len(lines):
            s = lines[i].strip()
            if not s or re.match(r"^(#|>|\||- |\d+\. |<!--)", s):
                break
            para.append(s)
            i += 1
        out.append(f"<p{take_pagebreak()}>{inline(' '.join(para))}</p>")
    return "\n".join(out)


def main():
    if len(sys.argv) != 3:
        sys.exit("Usage: install_guide_html.py INSTALL.md output.html")
    with open(sys.argv[1], encoding="utf-8") as f:
        lines = f.read().split("\n")
    title = next((l[2:].strip() for l in lines if l.startswith("# ")), "Installing DayBook AI")
    page = (
        '<!doctype html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n'
        f"<title>Start Here: {html.escape(title)}</title>\n<style>{CSS}</style>\n</head>\n<body>\n"
        f"{render(lines)}\n</body>\n</html>\n"
    )
    with open(sys.argv[2], "w", encoding="utf-8") as f:
        f.write(page)


if __name__ == "__main__":
    main()
