#!/usr/bin/env python3
"""Fallback converter for ingest.sh when pandoc and markitdown are not installed.

Usage: ingest_fallback.py <docx|pptx|xlsx|html> <input-file>
Writes markdown to stdout. Standard library only. Exit 1 on unreadable input.
"""
import html.parser
import re
import sys
import zipfile
import xml.etree.ElementTree as ET

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
A = "{http://schemas.openxmlformats.org/drawingml/2006/main}"
S = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
R = "{http://schemas.openxmlformats.org/officeDocument/2006/relationships}"
PR = "{http://schemas.openxmlformats.org/package/2006/relationships}"


def cell(text):
    return text.replace("|", "\\|").replace("\n", " ").strip()


def md_table(rows):
    rows = [r for r in rows if any(c.strip() for c in r)]
    if not rows:
        return []
    width = max(len(r) for r in rows)
    rows = [r + [""] * (width - len(r)) for r in rows]
    out = ["| " + " | ".join(cell(c) for c in rows[0]) + " |",
           "|" + "---|" * width]
    out += ["| " + " | ".join(cell(c) for c in r) + " |" for r in rows[1:]]
    return out + [""]


# ------------------------------------------------------------------ docx
def docx_para_text(p):
    parts = []
    for node in p.iter():
        if node.tag == W + "t":
            parts.append(node.text or "")
        elif node.tag == W + "tab":
            parts.append("\t")
        elif node.tag in (W + "br", W + "cr"):
            parts.append("\n")
    return "".join(parts).strip()


def docx(path):
    with zipfile.ZipFile(path) as z:
        root = ET.fromstring(z.read("word/document.xml"))
    body = root.find(W + "body")
    out = []
    for el in body:
        if el.tag == W + "p":
            text = docx_para_text(el)
            if not text:
                continue
            style = el.find(f"{W}pPr/{W}pStyle")
            sval = style.get(W + "val", "") if style is not None else ""
            m = re.match(r"(?i)heading\s*(\d)", sval)
            is_item = el.find(f"{W}pPr/{W}numPr") is not None or sval.lower().startswith("list")
            if not is_item and out and out[-1].startswith("- "):
                out.append("")   # end the list before the next block
            if m:
                out += ["#" * min(int(m.group(1)), 6) + " " + text, ""]
            elif sval.lower() == "title":
                out += ["# " + text, ""]
            elif is_item:
                out.append("- " + text)
            else:
                out += [text, ""]
        elif el.tag == W + "tbl":
            rows = [[docx_para_text(tc) for tc in tr.iter(W + "tc")] for tr in el.iter(W + "tr")]
            out += [""] + md_table(rows)
    return "\n".join(out)


# ------------------------------------------------------------------ pptx
def pptx(path):
    out = []
    with zipfile.ZipFile(path) as z:
        slides = sorted((n for n in z.namelist() if re.match(r"ppt/slides/slide\d+\.xml$", n)),
                        key=lambda n: int(re.findall(r"\d+", n)[-1]))
        for i, name in enumerate(slides, 1):
            root = ET.fromstring(z.read(name))
            out += [f"## Slide {i}", ""]
            for p in root.iter(A + "p"):
                text = "".join(t.text or "" for t in p.iter(A + "t")).strip()
                if text:
                    out.append("- " + text)
            out.append("")
    return "\n".join(out)


# ------------------------------------------------------------------ xlsx
def xlsx(path):
    out = []
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        shared = []
        if "xl/sharedStrings.xml" in names:
            for si in ET.fromstring(z.read("xl/sharedStrings.xml")).iter(S + "si"):
                shared.append("".join(t.text or "" for t in si.iter(S + "t")))
        rels = {r.get("Id"): r.get("Target") for r in
                ET.fromstring(z.read("xl/_rels/workbook.xml.rels")).iter(PR + "Relationship")}
        for sh in ET.fromstring(z.read("xl/workbook.xml")).iter(S + "sheet"):
            target = rels.get(sh.get(R + "id"), "")
            target = target.lstrip("/")
            target = target if target.startswith("xl/") else "xl/" + target
            if target not in names:
                continue
            rows = []
            for row in ET.fromstring(z.read(target)).iter(S + "row"):
                vals = {}
                for c in row.iter(S + "c"):
                    ref = re.match(r"([A-Z]+)", c.get("r", "A"))
                    col = 0
                    for ch in ref.group(1):
                        col = col * 26 + ord(ch) - 64
                    t, v = c.get("t"), c.find(S + "v")
                    if t == "s" and v is not None:
                        val = shared[int(v.text)]
                    elif t == "inlineStr":
                        val = "".join(x.text or "" for x in c.iter(S + "t"))
                    else:
                        val = v.text if v is not None and v.text else ""
                    vals[col] = val
                if vals:
                    rows.append([vals.get(i, "") for i in range(1, max(vals) + 1)])
            out += [f"## Sheet: {sh.get('name')}", ""] + (md_table(rows) or ["(empty)", ""])
    return "\n".join(out)


# ------------------------------------------------------------------ html
class HTMLToMarkdown(html.parser.HTMLParser):
    SKIP = {"script", "style", "noscript", "svg", "head", "template", "nav", "aside", "footer",
            "form", "button", "select", "dialog"}
    BLOCK = {"p", "div", "section", "article", "br", "tr", "table", "ul", "ol", "header", "footer", "main"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.out, self.skip, self.prefix = [], 0, ""

    def handle_starttag(self, tag, attrs):
        if tag in self.SKIP:
            self.skip += 1
        elif m := re.match(r"h([1-6])$", tag):
            self.out.append("\n\n" + "#" * int(m.group(1)) + " ")
        elif tag == "li":
            self.out.append("\n- ")
        elif tag in ("td", "th"):
            self.out.append(" | ")
        elif tag in self.BLOCK:
            self.out.append("\n\n")

    def handle_endtag(self, tag):
        if tag in self.SKIP and self.skip:
            self.skip -= 1
        elif re.match(r"h[1-6]$", tag) or tag in self.BLOCK:
            self.out.append("\n")

    def handle_data(self, data):
        if not self.skip:
            self.out.append(re.sub(r"\s+", " ", data))

    def markdown(self):
        text = "".join(self.out)
        text = re.sub(r"[ \t]+\n", "\n", text)
        return re.sub(r"\n{3,}", "\n\n", text).strip() + "\n"


def html_doc(path):
    p = HTMLToMarkdown()
    with open(path, encoding="utf-8", errors="replace") as f:
        doc = f.read()
    # keep only the main content when the page marks it
    for tag in ("main", "article"):
        m = re.search(rf"<{tag}\b[^>]*>(.*)</{tag}>", doc, re.S | re.I)
        if m and len(m.group(1)) > 500:
            doc = m.group(1)
            break
    p.feed(doc)
    return p.markdown()


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("docx", "pptx", "xlsx", "html"):
        print(__doc__, file=sys.stderr)
        return 2
    kind, path = sys.argv[1], sys.argv[2]
    try:
        text = {"docx": docx, "pptx": pptx, "xlsx": xlsx, "html": html_doc}[kind](path)
    except (zipfile.BadZipFile, KeyError, ET.ParseError, OSError) as e:
        print(f"cannot read {kind} file {path}: {e}", file=sys.stderr)
        return 1
    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
