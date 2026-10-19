from pathlib import Path
from xml.sax.saxutils import escape
from reportlab.pdfgen import canvas
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, KeepTogether
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib import colors
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.enums import TA_LEFT
ROOT=Path(__file__).resolve().parents[2]
for name,file in [('DejaVu','DejaVuSans.ttf'),('DejaVuBold','DejaVuSans-Bold.ttf')]:
    pdfmetrics.registerFont(TTFont(name,'/usr/share/fonts/truetype/dejavu/'+file))
styles={
 'title':ParagraphStyle('title',fontName='DejaVuBold',fontSize=19,leading=25,textColor=colors.HexColor('#205b45'),spaceAfter=18),
 'heading':ParagraphStyle('heading',fontName='DejaVuBold',fontSize=12,leading=17,textColor=colors.HexColor('#205b45'),spaceBefore=14,spaceAfter=7,keepWithNext=True),
 'body':ParagraphStyle('body',fontName='DejaVu',fontSize=9,leading=14,spaceAfter=8,splitLongWords=True),
}
def footer(c,d):
 c.setStrokeColor(colors.HexColor('#d8e7df'));c.line(42,36,553,36)
 c.setFont('DejaVu',8);c.setFillColor(colors.HexColor('#60746b'))
 c.drawString(42,23,'DOMLY • API для интеграции бота • v1.0');c.drawRightString(553,23,str(d.page))
for src,dst in [('bot-catalog.md','domly-bot-catalog.pdf'),('bot-area-verification.md','domly-bot-area-verification.pdf')]:
 story=[]
 for line in (ROOT/'docs/api'/src).read_text().splitlines():
  if not line.strip():continue
  kind='title' if line.startswith('# ') else 'heading' if line.startswith('## ') else 'body'
  text=line[2:] if kind=='title' else line[3:] if kind=='heading' else line
  story.append(Paragraph(escape(text),styles[kind]))
 target=ROOT/'backend/docs'/dst
 SimpleDocTemplate(str(target),pagesize=(595,842),leftMargin=42,rightMargin=42,topMargin=42,bottomMargin=49,title='DOMLY — '+src,author='DOMLY').build(story,onFirstPage=footer,onLaterPages=footer)
 print(target.name,target.stat().st_size)
