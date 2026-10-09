#!/usr/bin/env bash
# Sync App Store iPhone screenshots into the Doodloop marketing gallery.
#
# Expects captures from `fastlane screenshots` under ./screenshots/en-GB/.
# Writes PNGs into the sibling doodloop-website repo (override with DOODLOOP_WEB_ROOT).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="${SCREENSHOTS_DIR:-$ROOT/screenshots/en-GB}"
WEB_ROOT="${DOODLOOP_WEB_ROOT:-$ROOT/../doodloop-website}"
DEST_DIR="$WEB_ROOT/assets/screenshots"

# Match typical gallery asset size (iPhone 18 Pro Max @3x crop).
WEB_W=1206
WEB_H=2622

DEVICE_PREFIX="iPhone 18 Pro Max"

# Snapshot name → website gallery filename.
declare -a MAP=(
  "01-Home:01-home.png"
  "02-Lobby:02-lobby.png"
  "03-Drawing:03-drawing.png"
  "04-Guessing:04-guessing.png"
  "05-Reveal:05-reveal.png"
  "06-RoundOver:06-round-over.png"
)

if [[ ! -d "$SRC_DIR" ]]; then
  echo "error: missing screenshots dir: $SRC_DIR" >&2
  echo "Run \`fastlane screenshots\` first." >&2
  exit 1
fi

if [[ ! -d "$DEST_DIR" ]]; then
  mkdir -p "$DEST_DIR"
fi

echo "Syncing iPhone screenshots → $DEST_DIR"
for entry in "${MAP[@]}"; do
  name="${entry%%:*}"
  dest_name="${entry##*:}"
  src="$SRC_DIR/${DEVICE_PREFIX}-${name}.png"
  dest="$DEST_DIR/$dest_name"

  if [[ ! -f "$src" ]]; then
    echo "error: missing capture: $src" >&2
    exit 1
  fi

  # sips -z takes height then width.
  sips -z "$WEB_H" "$WEB_W" "$src" --out "$dest" >/dev/null
  echo "  ✓ $dest_name ← ${DEVICE_PREFIX}-${name}.png"
done

echo "Done. Commit marketing changes in: $WEB_ROOT"
