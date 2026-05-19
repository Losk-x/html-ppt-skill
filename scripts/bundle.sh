#!/usr/bin/env bash
# html-ppt :: bundle.sh — bundle a deck into a self-contained single HTML file
#   Inlines all CSS (theme, base, animations) and JS (runtime.js, fx-runtime.js).
#   Fixes @media print for PDF export.
#   Preserves data-theme-base for live theme switching.
#
# Usage:
#   bundle.sh <deck.html> [output.html]
#
# If output is omitted, writes to <deck-name>.bundle.html in the same directory.

set -euo pipefail

FILE="${1:-}"
OUT="${2:-}"

if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "usage: bundle.sh <deck.html> [output.html]" >&2
  exit 1
fi

HERE="$(cd "$(dirname "$0")/.." && pwd)"
ABS="$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")"
OUT="${OUT:-${FILE%.*}.bundle.html}"
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

# Pass paths via env vars to avoid bash interpolation into the Python heredoc
export PYTHON_ABS="$ABS"
export PYTHON_OUT="$OUT_ABS"
export PYTHON_HERE="$HERE"

python3 << 'PYEOF'
import os, re

abs_path = os.environ["PYTHON_ABS"]
out_path = os.environ["PYTHON_OUT"]
skill    = os.environ["PYTHON_HERE"]

with open(abs_path) as f:
    html = f.read()

# Read asset files
with open(f"{skill}/assets/base.css") as f:
    base_css = f.read()
with open(f"{skill}/assets/animations/animations.css") as f:
    anim_css = f.read()
with open(f"{skill}/assets/runtime.js") as f:
    runtime_js = f.read()

fx_runtime_path = f"{skill}/assets/animations/fx-runtime.js"
fx_runtime_js = ""
if os.path.exists(fx_runtime_path):
    with open(fx_runtime_path) as f:
        fx_runtime_js = f.read()

# Read current theme CSS (detect from #theme-link href, then fall back)
def read_theme_css():
    m = re.search(
        r'''<link[^>]*id=["']theme-link["'][^>]*href=["']([^"']+)["']''',
        html
    )
    if not m:
        with open(f"{skill}/assets/themes/tokyo-night.css") as f:
            return f.read()
    theme_href = m.group(1)
    theme_path = os.path.normpath(os.path.join(os.path.dirname(abs_path), theme_href))
    for candidate in (theme_path, f"{skill}/assets/themes/{os.path.basename(theme_href)}"):
        try:
            with open(candidate) as f:
                return f.read()
        except FileNotFoundError:
            continue
    with open(f"{skill}/assets/themes/tokyo-night.css") as f:
        return f.read()

theme_css = read_theme_css()
combined_css = theme_css + "\n" + base_css + "\n" + anim_css

# Inline runtime.js and fx-runtime.js FIRST (before removal loop)
def inline_script(html, keyword, content):
    pat = re.compile(
        rf'(<script\s+[^>]*src=(["\'])[^"\'"]*{re.escape(keyword)}[^"\'"]*\2[^>]*>)'
        rf'(.*?)</script>',
        re.IGNORECASE | re.DOTALL
    )
    return pat.sub(lambda m: f"<script>{content}</script>", html)

html = inline_script(html, "runtime.js", runtime_js)
if fx_runtime_js:
    html = inline_script(html, "fx-runtime.js", fx_runtime_js)

# Remove remaining external CSS/JS link/script tags (handle both " and ' quote styles)
QUOT = """["']"""

for pat_suffix in (
    'fonts\\.css',
    'base\\.css',
    'themes/[^"\'"]*\\.css',
    'animations\\.css',
):
    full_pat = rf'<link[^>]*href={QUOT}[^"\']*{pat_suffix}{QUOT}[^>]*>'
    html = re.sub(full_pat, '', html, flags=re.IGNORECASE)

for pat_suffix in (
    'runtime\\.js',
    'fx-runtime\\.js',
):
    full_pat = rf'<script[^>]*src={QUOT}[^"\']*{pat_suffix}{QUOT}[^>]*>.*?</script>'
    html = re.sub(full_pat, '', html, flags=re.IGNORECASE | re.DOTALL)

# Insert fonts @import before </head>
fonts = '''<style>
@import url("https://fonts.googleapis.com/css2?family=Inter:wght@200;300;400;500;600;700;800;900&display=swap");
@import url("https://fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@200;300;400;500;600;700;900&display=swap");
@import url("https://fonts.googleapis.com/css2?family=Noto+Serif+SC:wght@300;400;600;700&display=swap");
@import url("https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;700&display=swap");
@import url("https://fonts.googleapis.com/css2?family=Playfair+Display:ital,wght@0,400;0,600;0,800;1,400&display=swap");
@import url("https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@300;400;500;600;700&display=swap");
@import url("https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@300;400;500;700&display=swap");
@import url("https://fonts.googleapis.com/css2?family=Archivo+Black&display=swap");
</style>'''
html = html.replace("</head>", f"{fonts}<style>{combined_css}</style>\n</head>")

# Set data-theme-base to correct relative path from output to skill themes dir
out_dir = os.path.dirname(out_path)
theme_dir = os.path.join(skill, "assets", "themes")
rel = os.path.relpath(theme_dir, out_dir)

body_pat = re.compile(r'(<body\b[^>]*)(>)', re.IGNORECASE)

def set_theme_base(m):
    prefix = m.group(1)
    end = m.group(2)
    cleaned = re.sub(r'\s*data-theme-base="[^"]*"', '', prefix)
    return f'{cleaned} data-theme-base="{rel}/"{end}'

html = body_pat.sub(set_theme_base, html)

with open(out_path, "w") as f:
    f.write(html)

size = os.path.getsize(out_path)
print(f"Done: {size} bytes -> {out_path}")
PYEOF