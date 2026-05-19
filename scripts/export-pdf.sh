#!/usr/bin/env bash
# html-ppt :: export-pdf.sh — export a deck to PDF (one page per slide, 16:9)
#
# Usage:
#   export-pdf.sh <deck.html> [output.pdf]
#
# If output is omitted, writes to <deck-name>.pdf in the same directory.
#
# Requires: Google Chrome at /Applications (macOS).
#
# The deck is first bundled into a self-contained HTML (via bundle.sh) to
# avoid relative path issues. The PDF uses 16:9 widescreen slide dimensions.

set -euo pipefail

FILE="${1:-}"
OUT="${2:-}"

if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "usage: export-pdf.sh <deck.html> [output.pdf]" >&2
  echo "  e.g. export-pdf.sh examples/demo-deck/index.html demo.pdf" >&2
  exit 1
fi

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
if [[ ! -x "$CHROME" ]]; then
  echo "error: Chrome not found at $CHROME" >&2
  echo "  install Chrome or update the CHROME variable in this script" >&2
  exit 1
fi

OUT="${OUT:-${FILE%.*}.pdf}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

# Step 1: bundle into self-contained HTML
BUNDLE="${FILE%.*}.bundle.pdf-tmp.html"
"$HERE/scripts/bundle.sh" "$FILE" "$BUNDLE"
BUNDLE_ABS="$(cd "$(dirname "$BUNDLE")" && pwd)/$(basename "$BUNDLE")"

# Step 2: export via headless Chrome
"$CHROME" \
  --headless=new \
  --disable-gpu \
  --no-sandbox \
  --virtual-time-budget=6000 \
  --print-to-pdf="$OUT" \
  --window-size=1920,1080 \
  "file://$BUNDLE_ABS" >/dev/null 2>&1

# Step 3: clean up
rm -f "$BUNDLE"

echo "✔ exported PDF: $OUT"