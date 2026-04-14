#!/usr/bin/env python3
from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import Paragraph, Preformatted, SimpleDocTemplate, Spacer, PageBreak

ROOT = Path(__file__).resolve().parent
OUT_DIR = ROOT / "exports"
OUT_DIR.mkdir(parents=True, exist_ok=True)

DOCS = [
    "RUNBOOK_REPRODUCIBILIDAD.md",
    "RUNBOOK_ACADEMICO_METODO_EXPERIMENTAL.md",
    "CHECKLIST_VALIDACION_RAPIDA.md",
    "QUICKSTART_1PAGINA.md",
    "SECURITY_DEFENSIVE_ARGUMENT_IEEE_ACM.md",
    "ARGUMENTO_SEGURIDAD_DEFENSIVA_ES.md",
    "MAPEO_C1_C4_CSA_CCM_NIST.md",
]

MERGED_MD = OUT_DIR / "Documentacion_Unificada_muBench.md"
PDF_PATH = OUT_DIR / "Documentacion_Unificada_muBench.pdf"


def merge_markdown() -> str:
    parts = ["# Documentacion Unificada muBench\n"]
    parts.append("Documento generado automaticamente desde los archivos de RealisticServices.\n")

    for name in DOCS:
        path = ROOT / name
        if not path.exists():
            continue
        parts.append(f"\n## Fuente: {name}\n")
        parts.append(path.read_text(encoding="utf-8"))
        parts.append("\n")

    text = "\n".join(parts)
    MERGED_MD.write_text(text, encoding="utf-8")
    return text


def build_story(merged_text: str):
    styles = getSampleStyleSheet()
    h1 = styles["Heading1"]
    h2 = styles["Heading2"]
    h3 = styles["Heading3"]
    normal = styles["BodyText"]

    code_style = ParagraphStyle(
        "CodeBlock",
        parent=styles["Code"],
        fontName="Courier",
        fontSize=8.5,
        leading=10,
        backColor=colors.whitesmoke,
        borderColor=colors.lightgrey,
        borderWidth=0.5,
        borderPadding=5,
        leftIndent=6,
        rightIndent=6,
        spaceBefore=4,
        spaceAfter=6,
    )

    bullet_style = ParagraphStyle(
        "Bullet",
        parent=normal,
        leftIndent=14,
        spaceBefore=1,
        spaceAfter=1,
    )

    story = []
    in_code = False
    code_lines = []

    for raw in merged_text.splitlines():
        line = raw.rstrip("\n")

        if line.strip().startswith("```"):
            in_code = not in_code
            if not in_code:
                code_text = "\n".join(code_lines)
                story.append(Preformatted(code_text, code_style))
                code_lines = []
            continue

        if in_code:
            code_lines.append(line)
            continue

        if not line.strip():
            story.append(Spacer(1, 0.2 * cm))
            continue

        if line.startswith("# "):
            story.append(Paragraph(escape(line[2:].strip()), h1))
            story.append(Spacer(1, 0.2 * cm))
            continue

        if line.startswith("## "):
            heading = line[3:].strip()
            if heading.startswith("Fuente:") and len(story) > 0:
                story.append(PageBreak())
            story.append(Paragraph(escape(heading), h2))
            story.append(Spacer(1, 0.15 * cm))
            continue

        if line.startswith("### "):
            story.append(Paragraph(escape(line[4:].strip()), h3))
            story.append(Spacer(1, 0.1 * cm))
            continue

        stripped = line.lstrip()
        if stripped.startswith("- "):
            story.append(Paragraph(escape(stripped[2:].strip()), bullet_style, bulletText="•"))
            continue

        story.append(Paragraph(escape(line), normal))

    return story


def make_pdf(story):
    doc = SimpleDocTemplate(
        str(PDF_PATH),
        pagesize=A4,
        leftMargin=1.8 * cm,
        rightMargin=1.8 * cm,
        topMargin=1.8 * cm,
        bottomMargin=1.8 * cm,
        title="Documentacion Unificada muBench",
        author="muBench",
    )
    doc.build(story)


if __name__ == "__main__":
    merged_text = merge_markdown()
    story = build_story(merged_text)
    make_pdf(story)
    print(f"MERGED_MD={MERGED_MD}")
    print(f"PDF={PDF_PATH}")
