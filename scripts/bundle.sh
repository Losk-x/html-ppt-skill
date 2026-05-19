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
import os, re, json, glob, sys

abs_path = os.environ["PYTHON_ABS"]
out_path = os.environ["PYTHON_OUT"]
skill    = os.environ["PYTHON_HERE"]

def read_file(path, label="file"):
    try:
        with open(path) as f:
            return f.read()
    except FileNotFoundError:
        print(f"Error: {label} not found: {path}", file=__import__('sys').stderr)
        sys.exit(1)

html = read_file(abs_path, "Deck HTML")

# Read asset files
base_css = read_file(f"{skill}/assets/base.css", "base.css")
fonts_css = read_file(f"{skill}/assets/fonts.css", "fonts.css")
anim_css = read_file(f"{skill}/assets/animations/animations.css", "animations.css")
runtime_js = read_file(f"{skill}/assets/runtime.js", "runtime.js")

fx_runtime_path = f"{skill}/assets/animations/fx-runtime.js"
fx_runtime_js = ""
if os.path.exists(fx_runtime_path):
    try:
        with open(fx_runtime_path) as f:
            fx_runtime_js = f.read()
    except FileNotFoundError:
        print(f"Warning: fx-runtime.js not found, skipping", file=sys.stderr)

# Read ALL theme CSS files — inline them so no external loading is needed
theme_data = {}
themes_dir = f"{skill}/assets/themes"
if not os.path.isdir(themes_dir):
    print(f"Error: themes directory not found: {themes_dir}", file=sys.stderr)
    sys.exit(1)
for theme_file in sorted(glob.glob(f"{themes_dir}/*.css")):
    name = os.path.splitext(os.path.basename(theme_file))[0]
    try:
        with open(theme_file) as f:
            theme_data[name] = f.read()
    except FileNotFoundError:
        print(f"Warning: theme file vanished: {theme_file}", file=sys.stderr)

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
combined_css = base_css + "\n" + active_theme_css + "\n" + anim_css

# Inline runtime.js and fx-runtime.js FIRST (before removal loop)
def inline_script(html, keyword, content):
    pat = re.compile(
        rf'(<script\s+[^>]*src=(["\'])[^"\'"]*{re.escape(keyword)}[^"\'"]*\2[^>]*>)'
        rf'(.*?)</script>',
        re.IGNORECASE | re.DOTALL
    )
    return pat.sub(lambda m: f"<script>{content}</script>", html)

# Inject applyTheme override at the end of the IIFE (before })();
# This is robust: doesn't depend on the exact formatting of applyTheme in runtime.js.
# In strict mode, reassigning a function-scoped declaration is valid.
override_js = '''
  applyTheme = function(name) {
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
  };
'''
idx = runtime_js.rfind('})();')
if idx >= 0:
    runtime_js = runtime_js[:idx] + override_js + '\n' + runtime_js[idx:]

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
fonts_block = f"<style>\n{fonts_css}\n</style>"
theme_script = f'<script id="html-ppt-theme-data" type="application/json">{theme_json}</script>'
inject = f"{fonts_block}{theme_script}<style>{combined_css}</style>\n"
html = html.replace("</head>", inject + "</head>")

# Add window.__htmlPptThemeData initialization before the closing </body> or </html>
boot_script = f'<script>window.__htmlPptThemeData={theme_json};</script>'
if "</body>" in html:
    html = html.replace("</body>", boot_script + "\n</body>")
else:
    html = html.replace("</html>", boot_script + "\n</html>")

# Remove any remaining data-theme-base attribute (no longer needed)
html = re.sub(r'\s*data-theme-base="[^"]*"', '', html)

try:
    with open(out_path, "w") as f:
        f.write(html)
        f.write("\n")
except OSError as e:
    print(f"Error: cannot write to {out_path}: {e}", file=sys.stderr)
    sys.exit(1)

size = os.path.getsize(out_path)
print(f"Done: {size} bytes -> {out_path}")
PYEOF
