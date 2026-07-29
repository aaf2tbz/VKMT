#!/bin/bash
# Fetch and stage the pinned official Wine Mono runtime and matching source.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION=11.2.0
TAG="wine-mono-$VERSION"
BASE="https://github.com/wine-mono/wine-mono/releases/download/$TAG"
THIRD_PARTY="$VKMT/third_party"
MONO_ROOT="$VKMT/wine/mono"
RUNTIME_ARCHIVE="$THIRD_PARTY/$TAG-x86.tar.xz"
SOURCE_ARCHIVE="$THIRD_PARTY/$TAG-src.tar.xz"
RUNTIME_SHA=c9fb2e2823acf30b000b8806177db0f40751786136dd3f8fb2be7897b1643d06
SOURCE_SHA=aebef9b43dca80b3ebe4a0ada0f45925d833f371ba5b42f5acf9990461568ba9
STAGE="$MONO_ROOT/$TAG"
SOURCE_STAGE="$THIRD_PARTY/$TAG-src"

fetch()
{
  url=$1
  output=$2
  expected=$3
  if test -f "$output" &&
     printf '%s  %s\n' "$expected" "$output" | shasum -a 256 -c - >/dev/null 2>&1; then
    return
  fi
  test ! -e "$output" || {
    echo "Refusing to replace mismatched Wine Mono artifact: $output" >&2
    exit 1
  }
  curl --fail --location --retry 3 --output "$output.part" "$url"
  printf '%s  %s\n' "$expected" "$output.part" | shasum -a 256 -c -
  mv "$output.part" "$output"
}

mkdir -p "$THIRD_PARTY" "$MONO_ROOT"
fetch "$BASE/$TAG-x86.tar.xz" "$RUNTIME_ARCHIVE" "$RUNTIME_SHA"

if test ! -d "$STAGE"; then
  temporary="$(mktemp -d "$MONO_ROOT/.wine-mono-runtime.XXXXXX")"
  trap 'test -z "${temporary:-}" || rm -rf "$temporary"' EXIT
  tar -xJf "$RUNTIME_ARCHIVE" -C "$temporary"
  extracted="$temporary/$TAG"
  test -f "$extracted/bin/libmono-2.0-x86.dll"
  test -f "$extracted/bin/libmono-2.0-x86_64.dll"
  test -f "$extracted/lib/mono/4.5/mscorlib.dll"
  mv "$extracted" "$STAGE"
  rmdir "$temporary"
  temporary=
fi

if test "${VKMT_WINE_MONO_FETCH_SOURCE:-1}" = 1; then
  fetch "$BASE/$TAG-src.tar.xz" "$SOURCE_ARCHIVE" "$SOURCE_SHA"
  if test ! -d "$SOURCE_STAGE"; then
    temporary="$(mktemp -d "$THIRD_PARTY/.wine-mono-source.XXXXXX")"
    trap 'test -z "${temporary:-}" || rm -rf "$temporary"' EXIT
    tar -xJf "$SOURCE_ARCHIVE" -C "$temporary"
    extracted="$(find "$temporary" -mindepth 1 -maxdepth 1 -type d -print -quit)"
    test -n "$extracted"
    test -f "$extracted/GNUmakefile"
    mv "$extracted" "$SOURCE_STAGE"
    rmdir "$temporary"
    temporary=
  fi
fi

printf '%s  %s\n' "$RUNTIME_SHA" "$RUNTIME_ARCHIVE" | shasum -a 256 -c -
test -f "$STAGE/bin/libmono-2.0-x86.dll"
test -f "$STAGE/bin/libmono-2.0-x86_64.dll"
test -f "$STAGE/lib/mono/4.5/mscorlib.dll"
if test "${VKMT_WINE_MONO_FETCH_SOURCE:-1}" = 1; then
  printf '%s  %s\n' "$SOURCE_SHA" "$SOURCE_ARCHIVE" | shasum -a 256 -c -
  test -f "$SOURCE_STAGE/GNUmakefile"
fi

if test "${VKMT_WINE_MONO_BUILD_ARM64:-1}" = 1 &&
   test ! -f "$STAGE/bin/libmono-2.0.dll"; then
  VKMT_WINE_MONO_FETCHED=1 "$VKMT/scripts/build-wine-mono-arm64.sh"
fi
test -f "$STAGE/bin/libmono-2.0.dll"
file "$STAGE/bin/libmono-2.0.dll" |
  grep -q 'PE32+ executable (DLL).*Aarch64'

echo "VKMT_WINE_MONO_11_2_0_STAGE_OK"
