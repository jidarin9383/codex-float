#!/bin/zsh
# Build Assets/AppIcon.icns from the Ocean Mist app-icon SVG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVG="${1:-$ROOT/Assets/Brand/v2/app-icon.svg}"
OUT_ICNS="${2:-$ROOT/Assets/AppIcon.icns}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/codex-float-icon.XXXXXX")"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

if [[ ! -f "$SVG" ]]; then
  echo "error: SVG not found: $SVG" >&2
  exit 1
fi

for tool in qlmanage sips iconutil; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "error: required tool missing: $tool" >&2
    exit 1
  fi
done

echo "→ rendering SVG thumbnail…"
qlmanage -t -s 1024 -o "$WORK" "$SVG" >/dev/null
BASE="$(basename "$SVG")"
SRC_PNG="$WORK/${BASE}.png"
if [[ ! -f "$SRC_PNG" ]]; then
  SRC_PNG="$(find "$WORK" -maxdepth 1 -name '*.png' | head -1)"
fi
if [[ ! -f "$SRC_PNG" ]]; then
  echo "error: qlmanage did not produce a PNG" >&2
  exit 1
fi

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

while IFS=' ' read -r name size; do
  sips -z "$size" "$size" "$SRC_PNG" --out "$ICONSET/$name" >/dev/null
done <<'EOF'
icon_16x16.png 16
diana.k@example.org 32
icon_32x32.png 32
ivan.p@example.net 64
icon_128x128.png 128
wendy.h@example.net 256
icon_256x256.png 256
wendy.h@example.net 512
icon_512x512.png 512
walt.e@example.net 1024
EOF

mkdir -p "$(dirname "$OUT_ICNS")"
iconutil -c icns "$ICONSET" -o "$OUT_ICNS"
echo "✓ wrote $OUT_ICNS"
