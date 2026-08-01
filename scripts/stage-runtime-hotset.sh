#!/bin/bash
# Build, stage, and verify the native ARM64 bounded runtime hot-set prefetcher.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${WINEBUILDDIR:-$VKMT/wine/build-ec}"
SOURCE="$VKMT/tools/vkmt-hotset-prefetch.c"
SOURCE_MANIFEST="$VKMT/runtime/hotsets/all-arch-default.tsv"
RUNTIME="$BUILD/runtime/hotset"
TOOL="$RUNTIME/vkmt-hotset-prefetch"
MANIFEST="$RUNTIME/all-arch-default.tsv"
mode=ensure
prefix=

case $# in
  0) ;;
  1) test "$1" = --ensure || exit 2 ;;
  2)
    case "$1" in --prefix) mode=prefix ;; --verify-prefix) mode=verify ;; *) exit 2 ;; esac
    prefix=$2
    ;;
  *) exit 2 ;;
esac

test -f "$SOURCE" && test -f "$SOURCE_MANIFEST"
mkdir -p "$RUNTIME"
if test ! -x "$TOOL" || test "$SOURCE" -nt "$TOOL"; then
  /usr/bin/clang -O2 -Wall -Wextra -Werror "$SOURCE" -o "$TOOL.new"
  test "$(/usr/bin/lipo -archs "$TOOL.new")" = arm64
  mv -f "$TOOL.new" "$TOOL"
fi
if test ! -f "$MANIFEST" || ! cmp -s "$SOURCE_MANIFEST" "$MANIFEST"; then
  install -m 0644 "$SOURCE_MANIFEST" "$MANIFEST.new"
  mv -f "$MANIFEST.new" "$MANIFEST"
fi

tool_sha="$(shasum -a 256 "$TOOL" | awk '{print $1}')"
manifest_sha="$(shasum -a 256 "$MANIFEST" | awk '{print $1}')"
entries=$(( $(wc -l <"$MANIFEST") - 1 ))
bytes="$(awk -F '\t' 'NR > 1 {sum += $4} END {print sum + 0}' "$MANIFEST")"
test "$entries" -gt 0 && test "$bytes" -gt 0 && test "$bytes" -le 268435456

if test "$mode" = prefix; then
  mkdir -p "$prefix/.vkmt"
  printf 'tool_sha256=%s\nmanifest_sha256=%s\nentries=%s\nbytes=%s\n' \
    "$tool_sha" "$manifest_sha" "$entries" "$bytes" >"$prefix/.vkmt/hotset-runtime.receipt.new"
  mv -f "$prefix/.vkmt/hotset-runtime.receipt.new" "$prefix/.vkmt/hotset-runtime.receipt"
elif test "$mode" = verify; then
  receipt="$prefix/.vkmt/hotset-runtime.receipt"
  test -f "$receipt"
  grep -Fqx "tool_sha256=$tool_sha" "$receipt"
  grep -Fqx "manifest_sha256=$manifest_sha" "$receipt"
  grep -Fqx "entries=$entries" "$receipt"
  grep -Fqx "bytes=$bytes" "$receipt"
fi

marker="$(printf '%s' "$mode" | tr '[:lower:]' '[:upper:]')"
echo "VKMT_HOTSET_RUNTIME_${marker}_OK entries=$entries bytes=$bytes"
