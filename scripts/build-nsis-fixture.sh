#!/bin/bash
# Build the i386 NSIS lifecycle fixture with native ARM64 host tools.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$VKMT/build/installer-fixtures"
CC="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin/i686-w64-mingw32-gcc"
MAKENSIS="${MAKENSIS:-$(command -v makensis)}"

test -x "$CC" || {
  echo "Missing in-tree i386 compiler: $CC" >&2
  exit 1
}
test -n "$MAKENSIS" && test -x "$MAKENSIS" || {
  echo "Missing NSIS compiler: makensis" >&2
  exit 1
}
test "$(/usr/bin/lipo -archs "$MAKENSIS")" = arm64 || {
  echo "NSIS compiler is not native ARM64: $MAKENSIS" >&2
  exit 1
}

mkdir -p "$OUTPUT"
"$CC" -O2 -s -o "$OUTPUT/vkmt-nsis-payload.exe" "$VKMT/test/nsis_payload.c"
(
  cd "$OUTPUT"
  "$MAKENSIS" -V2 \
    -DVKMT_NSIS_PAYLOAD="$OUTPUT/vkmt-nsis-payload.exe" \
    -DVKMT_NSIS_OUTFILE="$OUTPUT/vkmt-nsis-probe.exe" \
    "$VKMT/test/installers/vkmt-nsis.nsi"
)

echo INSTALLER_FIXTURE_NSIS_I386_OK
