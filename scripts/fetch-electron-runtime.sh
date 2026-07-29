#!/bin/bash
# Fetch and extract the pinned Electron release retaining x64 and ia32 Windows.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION='42.7.1'
DEST="$VKMT/third_party/electron-$VERSION"
BASE="https://github.com/electron/electron/releases/download/v$VERSION"

fetch()
{
  arch=$1
  expected=$2
  name="electron-v$VERSION-win32-$arch.zip"
  mkdir -p "$DEST"
  if test ! -f "$DEST/$name"; then
    curl -L --fail --show-error --progress-bar "$BASE/$name" \
      -o "$DEST/$name.part"
    mv "$DEST/$name.part" "$DEST/$name"
  fi
  actual="$(shasum -a 256 "$DEST/$name" | awk '{print $1}')"
  if test "$actual" != "$expected"; then
    echo "$name SHA-256 mismatch: $actual" >&2
    exit 1
  fi
  stage="$DEST/windows-$arch"
  if test ! -f "$stage/electron.exe"; then
    mkdir -p "$stage"
    unzip -q -o "$DEST/$name" -d "$stage"
  fi
}

fetch x64 2328058c825548541059d421f7deb7ded3ad281ae1b93bcd7cbb6d2e161a950c
fetch ia32 ee27a1906b61f712d66d155017539592477eeb094eec1c2ff3b2b468106efa56
echo ELECTRON_42_X64_I386_STAGE_OK
