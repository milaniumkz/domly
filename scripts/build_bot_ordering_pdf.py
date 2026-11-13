"""Build the owner's PRIVATE token-bearing PDF outside the Git repository.
Usage: python3 scripts/build_bot_ordering_pdf.py --token-file /private/key --output /tmp/DomLY-MooonAI.pdf
Only run after the token was installed and the production API verified.
"""
import argparse
from pathlib import Path
from xml.sax.saxutils import escape
from reportlab.platypus import SimpleDocTemplate, Paragraph
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.colors import HexColor

parser = argparse.ArgumentParser()
parser.add_argument('--token-file', required=True)
parser.add_argument('--output', required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
out = Path(args.output).resolve()
if out.is_relative_to(root):
    parser.error('Private PDF must be created outside the repository')
token = Path(args.token_file).read_text().strip()
if len(token) < 32 or any(c.isspace() for c in token):
    parser.error('Invalid ordering token')
for name, file in [('Body', 'DejaVuSans.ttf'), ('Bold', 'DejaVuSans-Bold.ttf')]:
    pdfmetrics.registerFont(TTFont(name, '/usr/share/fonts/truetype/dejavu/' + file))
styles = {
    'title': ParagraphStyle('title', fontName='Bold', fontSize=18, leading=24, spaceAfter=16, textColor=HexColor('#205b45')),
    'heading': ParagraphStyle('heading', fontName='Bold', fontSize=11, leading=16, spaceBefore=12, spaceAfter=6, keepWithNext=True),
    'body': ParagraphStyle('body', fontName='Body', fontSize=9, leading=14, spaceAfter=8, splitLongWords=True),
}
story = [Paragraph('DomLY · MooonAI · Закрытый доступ', styles['title']),
         Paragraph('Токен для заголовка X-MoonAI-Ordering-Token:', styles['heading']),
         Paragraph(escape(token), styles['body']),
         Paragraph('Не пересылайте документ клиентам. Он предоставляет боту доступ к оформлению покупок и заказов.', styles['body'])]
for line in (root/'docs/api/bot-ordering.md').read_text().splitlines():
    if not line.strip():
        continue
    kind = 'title' if line.startswith('# ') else 'heading' if line.startswith('## ') else 'body'
    story.append(Paragraph(escape(line.lstrip('# ') if kind != 'body' else line), styles[kind]))
def footer(c, doc):
    c.setFont('Body', 8)
    c.drawString(42, 24, 'DomLY · Конфиденциально · Доступ для MooonAI')
    c.drawRightString(553, 24, str(doc.page))
out.parent.mkdir(parents=True, exist_ok=True)
# Reserve privately before ReportLab opens the file (no world-readable window).
import os
fd = os.open(out, os.O_CREAT | os.O_TRUNC | os.O_WRONLY, 0o600)
os.close(fd)
os.chmod(out, 0o600)
SimpleDocTemplate(str(out), pagesize=(595, 842), leftMargin=42, rightMargin=42,
                  topMargin=42, bottomMargin=48, title='DomLY — MooonAI API', author='DomLY').build(story, onFirstPage=footer, onLaterPages=footer)
print('Private PDF created')
