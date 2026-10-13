#!/usr/bin/env python3
"""Generate Phase 2 requirement fixtures (stdlib only).

The "TodoNow" requirement is deliberately incomplete and contradictory:
brief.md says email/password login only, meeting-notes.docx says Google sign-in.
Usage: make_fixtures.py <out-dir>
"""
import os
import sys
import zipfile
import zlib

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
os.makedirs(OUT, exist_ok=True)

BRIEF = """# TodoNow: product brief

We want a simple todo app for busy families.

## Login
Users must log in before they can see their tasks. Login is by **email and password only**;
we do not want any third-party login providers.

## Tasks
- A user can create a task with a title and a due date.
- A user can mark a task as done.
- Overdue tasks should stand out.

## Notes
Reminders would be nice. Budget is small, launch before Tet.
"""

CT = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
{overrides}
</Types>"""
RELS = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">{rels}</Relationships>"""


def rel(i, typ, target):
    return (f'<Relationship Id="rId{i}" Type="http://schemas.openxmlformats.org/officeDocument/2006/'
            f'relationships/{typ}" Target="{target}"/>')


def docx(path):
    W = 'xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"'

    def p(text, style=None, num=False):
        ppr = ""
        if style or num:
            ppr = "<w:pPr>" + (f'<w:pStyle w:val="{style}"/>' if style else "") + \
                  ('<w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr>' if num else "") + "</w:pPr>"
        return f"<w:p>{ppr}<w:r><w:t xml:space=\"preserve\">{text}</w:t></w:r></w:p>"

    def tbl(rows):
        return "<w:tbl>" + "".join(
            "<w:tr>" + "".join(f"<w:tc>{p(c)}</w:tc>" for c in r) + "</w:tr>" for r in rows) + "</w:tbl>"

    body = "".join([
        p("Meeting notes: TodoNow kickoff (2026-10-01)", "Title"),
        p("Decisions", "Heading1"),
        p("Users sign in with their Google account, for convenience.", num=True),
        p("Tasks can be shared with family members.", num=True),
        p("Each task has a priority.", num=True),
        p("Priorities", "Heading2"),
        tbl([["Priority", "Meaning"], ["High", "Today"], ["Normal", "This week"], ["Low", "Some day"]]),
        p("Open point: does a shared task notify the other family members? Not decided."),
    ])
    doc = f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document {W}><w:body>{body}</w:body></w:document>'
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", CT.format(overrides='<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'))
        z.writestr("_rels/.rels", RELS.format(rels=rel(1, "officeDocument", "word/document.xml")))
        z.writestr("word/document.xml", doc)


def pptx(path):
    A = 'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"'
    slides = [["TodoNow", "Family todo app"], ["Goals", "Launch before Tet", "100 families in the first month"]]
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", CT.format(overrides="".join(
            f'<Override PartName="/ppt/slides/slide{i}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>'
            for i in range(1, len(slides) + 1))))
        for i, lines in enumerate(slides, 1):
            paras = "".join(f"<a:p><a:r><a:t>{t}</a:t></a:r></a:p>" for t in lines)
            z.writestr(f"ppt/slides/slide{i}.xml",
                       f'<?xml version="1.0" encoding="UTF-8"?><p:sld {A}><p:cSld><p:spTree><p:sp><p:txBody>{paras}</p:txBody></p:sp></p:spTree></p:cSld></p:sld>')


def xlsx(path):
    S = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
    rows = [["Field", "Type", "Required"], ["title", "text", "yes"], ["due_date", "date", "no"], ["priority", "High/Normal/Low", "?"]]
    shared = sorted({c for r in rows for c in r})
    idx = {s: i for i, s in enumerate(shared)}
    cols = "ABC"
    data = "".join(f'<row r="{ri}">' + "".join(
        f'<c r="{cols[ci]}{ri}" t="s"><v>{idx[c]}</v></c>' for ci, c in enumerate(r)) + "</row>"
        for ri, r in enumerate(rows, 1))
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("[Content_Types].xml", CT.format(overrides=""))
        z.writestr("xl/workbook.xml", f'<workbook {S}><sheets><sheet name="Task fields" sheetId="1" r:id="rId1"/></sheets></workbook>')
        z.writestr("xl/_rels/workbook.xml.rels", RELS.format(rels=rel(1, "worksheet", "worksheets/sheet1.xml")))
        z.writestr("xl/worksheets/sheet1.xml", f"<worksheet {S}><sheetData>{data}</sheetData></worksheet>")
        z.writestr("xl/sharedStrings.xml", f"<sst {S}>" + "".join(f"<si><t>{s}</t></si>" for s in shared) + "</sst>")


def pdf(path, objects):
    out, offs = bytearray(b"%PDF-1.4\n"), []
    for i, obj in enumerate(objects, 1):
        offs.append(len(out))
        out += f"{i} 0 obj\n".encode() + obj + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n".encode()
    out += b"".join(f"{o:010d} 00000 n \n".encode() for o in offs)
    out += f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    open(path, "wb").write(out)


def stream(data, extra=b""):
    return b"<< /Length %d %s >>\nstream\n" % (len(data), extra) + data + b"\nendstream"


def text_pdf(path):
    lines = ["TodoNow - non-functional requirements", "",
             "1. Works on mobile browsers (Chrome Android, Safari iOS).",
             "2. Pages load in under 2 seconds on 4G.",
             "3. The interface is available in Vietnamese and English.",
             "4. Personal data must be stored securely."]
    ops = "BT /F1 12 Tf 50 780 Td 16 TL " + " ".join(f"({l}) Tj T*" for l in lines) + " ET"
    pdf(path, [b"<< /Type /Catalog /Pages 2 0 R >>",
               b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
               b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
               b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
               stream(ops.encode())])


def scanned_pdf(path):
    w, h = 200, 60   # a gray box with a dark bar: an image, no text layer
    raw = bytearray()
    for y in range(h):
        for x in range(w):
            raw += b"\x30" if 20 < y < 40 and 20 < x < 180 else b"\xd0"
    img = zlib.compress(bytes(raw))
    pdf(path, [b"<< /Type /Catalog /Pages 2 0 R >>",
               b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
               b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /XObject << /Im1 4 0 R >> >> /Contents 5 0 R >>",
               stream(img, b"/Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode" % (w, h)),
               stream(b"q 400 120 0 0 100 600 cm /Im1 Do Q")])


open(os.path.join(OUT, "brief.md"), "w").write(BRIEF)
docx(os.path.join(OUT, "meeting-notes.docx"))
pptx(os.path.join(OUT, "pitch.pptx"))
xlsx(os.path.join(OUT, "fields.xlsx"))
text_pdf(os.path.join(OUT, "nfr.pdf"))
scanned_pdf(os.path.join(OUT, "scanned.pdf"))
print("fixtures written to", OUT)
