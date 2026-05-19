#!/usr/bin/env bash
# html-ppt :: bundle.sh — bundle a deck into a self-contained single HTML file
#   Inlines ALL themes, base CSS, animations, and JS (runtime.js, fx-runtime.js).
#   Theme switching uses inlined data — no external files needed.
#   Fixes @media print for PDF export.
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
import os, re, json, glob

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

# Read ALL theme CSS files — inline them so no external loading is needed
theme_data = {}
for theme_file in sorted(glob.glob(f"{skill}/assets/themes/*.css")):
    name = os.path.splitext(os.path.basename(theme_file))[0]
    with open(theme_file) as f:
        theme_data[name] = f.read()

theme_json = json.dumps(theme_data, ensure_ascii=False)

# Determine current active theme from the deck HTML
current_theme_match = re.search(
    r'''<link[^>]*id=["']theme-link["'][^>]*href=["']([^"']+)["']''',
    html
)
if current_theme_match:
    current_theme = os.path.splitext(os.path.basename(current_theme_match.group(1)))[0]
else:
    m = re.search(r'data-theme\s*=\s*"([^"]+)"', html)
    current_theme = m.group(1) if m else "tokyo-night"

# Use the current theme's CSS in the main combined block
active_theme_css = theme_data.get(current_theme, theme_data.get("tokyo-night", ""))
combined_css = active_theme_css + "\n" + base_css + "\n" + anim_css

# Inline runtime.js and fx-runtime.js FIRST (before removal loop)
def inline_script(html, keyword, content):
    pat = re.compile(
        rf'(<script\s+[^>]*src=(["\'])[^"\'"]*{re.escape(keyword)}[^"\'"]*\2[^>]*>)'
        rf'(.*?)</script>',
        re.IGNORECASE | re.DOTALL
    )
    return pat.sub(lambda m: f"<script>{content}</script>", html)

# Before inlining, patch applyTheme in runtime_js to use inlined theme data
old_apply = '''    function applyTheme(name) {
      let link = document.getElementById('theme-link');
      if (!link) {
        link = document.createElement('link');
        link.rel = 'stylesheet';
        link.id = 'theme-link';
        document.head.appendChild(link);
      }
      link.href = themeBase + name + '.css';
      root.setAttribute('data-theme', name);
      const ind = document.querySelector('.theme-indicator');
      if (ind) ind.textContent = name;
    }'''

new_apply = '''    function applyTheme(name) {
      let style = document.getElementById('theme-style');
      if (!style) {
        style = document.createElement('style');
        style.id = 'theme-style';
        document.head.appendChild(style);
      }
      const data = window.__htmlPptThemeData || {};
      style.textContent = data[name] || '';
      root.setAttribute('data-theme', name);
      const ind = document.querySelector('.theme-indicator');
      if (ind) ind.textContent = name;
    }'''

runtime_js = runtime_js.replace(old_apply, new_apply)

html = inline_script(html, "runtime.js", runtime_js)
if fx_runtime_js:
    html = inline_script(html, "fx-runtime.js", fx_runtime_js)

# Remove remaining external CSS/JS link/script tags
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

# Insert fonts @import + theme data + combined CSS before </head>
fonts = '''<style>
@import url("https://fonts.googleapis.com/css2?family=Inter:wght@200;300;400;500;600;700;800;900&display=swap");
@import url("https://fonts.googleapis.com/css2?family=Noto+Sans+SC:wght@200;300;400;500;600;700;900&display=swap");
@import url("https://fonts.googleapis.com/css2?family=Noto+Serif+SC:wght@200;300;400;500;600;700;900&display=swap");
@import url("https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;500;700&display=swap");
@import url("https://fonts.googleapis.com/css2?family=Playfair+Display:ital,wght@0,400;0,600;0,800;1,400&display=swap");
@import url("https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@300;400;500;600;700&display=swap");
@import url("https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@300;400;500;700&display=swap");
@import url("https://fonts.googleapis.com/css2?family=Archivo+Black&display=swap");
</style>'''
theme_script = f'<script id="html-ppt-theme-data" type="application/json">{theme_json}</script>'
inject = f"{fonts}{theme_script}<style>{combined_css}</style>\n"
html = html.replace("</head>", inject + "</head>")

# Add window.__htmlPptThemeData initialization before the closing </body> or </html>
boot_script = f'<script>window.__htmlPptThemeData={theme_json};</script>'
if "</body>" in html:
    html = html.replace("</body>", boot_script + "\n</body>")
else:
    html = html.replace("</html>", boot_script + "\n</html>")

# Remove any remaining data-theme-base attribute (no longer needed)
html = re.sub(r'\s*data-theme-base="[^"]*"', '', html)

with open(out_path, "w") as f:
    f.write(html)

size = os.path.getsize(out_path)
print(f"Done: {size} bytes -> {out_path}")
PYEOF