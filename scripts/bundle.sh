#!/usr/bin/env bash
# html-ppt :: bundle.sh — bundle a deck into a self-contained single HTML file
#   Inlines all CSS (theme, base, animations) and JS (runtime.js).
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
DIR="$(dirname "$FILE")"
OUT="${OUT:-${FILE%.*}.bundle.html}"

python3 << PYEOF
import os, re

with open("$ABS") as f:
    html = f.read()

skill = "$HERE"

# Read asset files
with open(f"{skill}/assets/base.css") as f:
    base_css = f.read()
with open(f"{skill}/assets/animations/animations.css") as f:
    anim_css = f.read()
with open(f"{skill}/assets/runtime.js") as f:
    runtime_js = f.read()

# Read current theme CSS (from #theme-link or fallback to tokyo-night)
theme_match = re.search(r'<link[^>]*id="theme-link"[^>]*href="([^"]*)"', html)
if theme_match:
    theme_href = theme_match.group(1)
    theme_path = os.path.normpath(os.path.join(os.path.dirname("$ABS"), theme_href))
    try:
        with open(theme_path) as f:
            theme_css = f.read()
    except FileNotFoundError:
        # Fall back to the skill's theme dir
        theme_name = os.path.splitext(os.path.basename(theme_href))[0]
        with open(f"{skill}/assets/themes/{theme_name}.css") as f:
            theme_css = f.read()
else:
    with open(f"{skill}/assets/themes/tokyo-night.css") as f:
        theme_css = f.read()

combined_css = theme_css + "\n" + base_css + "\n" + anim_css

# Remove external CSS/JS links
html = re.sub(r'<link[^>]*href="[^"]*fonts\.css"[^>]*>', '', html)
html = re.sub(r'<link[^>]*href="[^"]*base\.css"[^>]*>', '', html)
html = re.sub(r'<link[^>]*href="[^"]*themes/[^"]*\.css"[^>]*>', '', html)
html = re.sub(r'<link[^>]*href="[^"]*animations\.css"[^>]*>', '', html)
html = re.sub(r'<script[^>]*src="[^"]*runtime\.js"[^>]*>.*?</script>', '', html)
html = re.sub(r'<script[^>]*src="[^"]*fx-runtime\.js"[^>]*>.*?</script>', '', html)

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

# Inline runtime.js
if '<script src=' in html:
    html = html.replace('<script src="', '<script data-src="')
marker = '<script data-src="'
idx = html.find(marker)
while idx >= 0:
    end = html.find('>', idx)
    tag = html[idx:end+1]
    if 'runtime.js' in tag:
        before = html[:idx]
        after = html[end+1:]
        html = before + f"<script>{runtime_js}</script>" + after
        break
    idx = html.find(marker, end)
html = html.replace('<script data-src="', '<script src="')

# Set data-theme-base to correct relative path from output to skill themes dir
out_dir = os.path.dirname(os.path.abspath("$OUT"))
theme_dir = os.path.join(skill, "assets", "themes")
rel = os.path.relpath(theme_dir, out_dir)

body_pat = re.compile(r'(<body\b[^>]*)(>)', re.IGNORECASE)
if body_pat.search(html):
    # Remove existing data-theme-base if present, then re-add
    html = re.sub(r'\s*data-theme-base="[^"]*"', '', html)
    html = body_pat.sub(r'\1 data-theme-base="' + rel + '/"\2', html)

with open("$OUT", "w") as f:
    f.write(html)

size = os.path.getsize("$OUT")
print(f"Done: {size} bytes -> $OUT")
PYEOF