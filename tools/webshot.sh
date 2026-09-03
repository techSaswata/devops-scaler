#!/usr/bin/env bash
# Real headless-Chrome screenshot of a live URL.
# usage: webshot.sh <url> <out.png> [width] [height]
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
URL="$1"; OUT="$2"; W="${3:-1200}"; H="${4:-820}"
mkdir -p "$(dirname "$OUT")"
"$CHROME" --headless --disable-gpu --hide-scrollbars \
  --force-device-scale-factor=2 \
  --virtual-time-budget=4000 \
  --screenshot="$OUT" --window-size="$W,$H" "$URL" 2>/dev/null
[ -f "$OUT" ] && echo "  shot: $OUT ($(du -h "$OUT" | cut -f1))" || echo "  FAILED: $OUT"
