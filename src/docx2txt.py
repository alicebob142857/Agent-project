import zipfile
import re
import html
from pathlib import Path

docx = Path("instructions.docx")

with zipfile.ZipFile(docx) as z:
    xml = z.read("word/document.xml").decode("utf-8")

xml = xml.replace("</w:p>", "\n")
text = re.sub(r"<[^>]+>", "", xml)
text = html.unescape(text)

print(text)