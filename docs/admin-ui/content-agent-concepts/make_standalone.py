"""Package the concept into an offline HTML file, including fonts and sample media."""
import base64
import mimetypes
from pathlib import Path

root = Path(__file__).resolve().parent
css = (root / "styles.css").read_text() + "\n" + (root / "page-preview.css").read_text()
script = (root / "page-preview.js").read_text() + "\n" + (root / "app.js").read_text()

for path in (root / "media").iterdir():
    mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    data_url = f"data:{mime};base64,{base64.b64encode(path.read_bytes()).decode()}"
    relative = f"media/{path.name}"
    css = css.replace(relative, data_url)
    script = script.replace(relative, data_url)

html = (root / "index.html").read_text()
html = html.replace('<link rel="stylesheet" href="styles.css">', f"<style>{css}</style>")
html = html.replace('<link rel="stylesheet" href="page-preview.css">', "")
html = html.replace('<script src="page-preview.js"></script>', "")
html = html.replace('<script src="app.js"></script>', f"<script>{script}</script>")
html = "\n".join(line.rstrip() for line in html.splitlines()) + "\n"
target = root / "concepts.html"
target.write_text(html)
print(f"Created {target.name} ({target.stat().st_size:,} bytes)")
