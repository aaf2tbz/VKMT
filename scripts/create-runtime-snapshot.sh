#!/bin/bash
# Create a directly compressed, verified recovery image of the complete VKMT tree.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
SNAPSHOT_DIR="${VKMT_SNAPSHOT_DIR:-/Volumes/AverySSD/VKMT_snapshots}"
STAMP="${VKMT_SNAPSHOT_STAMP:-$(date +%Y%m%d-%H%M%S)}"
NAME="VKMT-runtime-phase2-$STAMP"
ARCHIVE="$SNAPSHOT_DIR/$NAME.tar.zst"
CHECKSUM="$ARCHIVE.sha256"
MANIFEST="$SNAPSHOT_DIR/$NAME.manifest.txt"

mkdir -p "$SNAPSHOT_DIR"
test ! -e "$ARCHIVE"

tar -c -C "$(dirname "$VKMT")" \
  --exclude='VKMT/.git' \
  --exclude='VKMT/*/.git' \
  --exclude='VKMT/*/*/.git' \
  --exclude='VKMT/build/probe-runs' \
  --exclude='VKMT/**/CMakeFiles' \
  --exclude='VKMT/**/.cache' \
  --exclude='VKMT/**/*.log' \
  --exclude='VKMT/**/*.zip' \
  --exclude='VKMT/**/*.dmg' \
  --exclude='VKMT/**/*.tar.gz' \
  VKMT |
  zstd -T0 -19 --long=31 -o "$ARCHIVE"

zstd -t --long=31 "$ARCHIVE"
zstd -dc --long=31 "$ARCHIVE" | tar -tf - >"$MANIFEST"
for required in \
  VKMT/AGENTS.md \
  VKMT/wine/build-ec/wine \
  VKMT/wine/build-ec/server/wineserver \
  VKMT/wine/wine-11.12/runtime-providers/xtajit64-arm64ec-known-good.dll \
  VKMT/wine/wine-11.12/runtime-providers/xtajit-arm64-known-good.dll \
  VKMT/scripts/stage-runtime-providers.sh \
  VKMT/scripts/probe-p6-single-prefix-architectures.sh; do
  grep -Fxq "$required" "$MANIFEST"
done
shasum -a 256 "$ARCHIVE" >"$CHECKSUM"

printf 'VKMT_RUNTIME_SNAPSHOT_OK\narchive=%s\nchecksum=%s\nmanifest=%s\n' \
  "$ARCHIVE" "$CHECKSUM" "$MANIFEST"
