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

# Resolve to absolute paths
ABS_FILE="$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")"
OUT="${OUT:-${ABS_FILE%.*}.pdf}"
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

# Temp bundle — place alongside the input file so relative paths resolve
BUNDLE="${ABS_FILE%.*}.bundle.pdf-tmp.html"
cleanup() { rm -f "$BUNDLE"; }
trap cleanup EXIT

# Step 1: bundle into self-contained HTML
"$HERE/scripts/bundle.sh" "$ABS_FILE" "$BUNDLE"

# Step 2: export via headless Chrome
if ! "$CHROME" \
  --headless=new \
  --disable-gpu \
  --no-sandbox \
  --virtual-time-budget=10000 \
  --print-to-pdf="$OUT_ABS" \
  --window-size=1920,1080 \
  "file://$BUNDLE" >/dev/null 2>&1; then
  echo "error: Chrome exited with non-zero status" >&2
  exit 1
fi

# Step 3: verify PDF was produced
if [[ ! -f "$OUT_ABS" || ! -s "$OUT_ABS" ]]; then
  echo "error: PDF output is empty or missing: $OUT_ABS" >&2
  exit 1
fi

echo "✔ exported PDF: $OUT_ABS"
