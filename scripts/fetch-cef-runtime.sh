#!/bin/bash
# Fetch the pinned official CEF client distributions used by Phase D probes.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION='109.1.18+gf1c41e4+chromium-109.0.5414.120'
BASE='https://cef-builds.spotifycdn.com'
DEST="$VKMT/third_party/cef-$VERSION"

fetch()
{
  arch=$1
  expected=$2
  name="cef_binary_${VERSION}_windows${arch}_client.tar.bz2"
  mkdir -p "$DEST"
  if test ! -f "$DEST/$name"; then
    curl -L --fail --show-error --progress-bar "$BASE/$name" -o "$DEST/$name.part"
    mv "$DEST/$name.part" "$DEST/$name"
  fi
  actual="$(shasum "$DEST/$name" | awk '{print $1}')"
  if test "$actual" != "$expected"; then
    echo "$name SHA-1 mismatch: $actual" >&2
    exit 1
  fi
  if test ! -d "$DEST/windows$arch"; then
    extracted="$DEST/.extract-windows$arch"
    mkdir -p "$extracted"
    tar -xjf "$DEST/$name" -C "$extracted"
    root="$(find "$extracted" -mindepth 1 -maxdepth 1 -type d -print -quit)"
    test -n "$root"
    mv "$root" "$DEST/windows$arch"
    /usr/bin/trash "$extracted" 2>/dev/null || true
  fi
}

fetch 32 94d415d7da529d13838b7fc2ec2ae15a8ed866fe
fetch 64 c8632a4a14b1bf3e034dc487cae74969d5393471
echo CEF_109_CLIENT_X86_X64_STAGE_OK
