#!/bin/bash
# Build and run the x64-on-ARM64 DXMT probe; rejects i386 and x86_64 Unixlibs.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
LLVM_MINGW="${LLVM_MINGW:-/Volumes/AverySSD/toolchains/llvm-mingw-20260616-ucrt-macos-universal}"
STAGE="$VKMT/wine/build-ec/dxmt-v0.80"
PROBE="$VKMT/test/dxmt_x64_probe.exe"
LOG="${TMPDIR:-/tmp}/vkmt-dxmt-x64-probe.log"
PREFIX="${WINEPREFIX:-$HOME/Library/Caches/VKMT-DXMT-x64-prefix}"

test -f "$STAGE/aarch64-windows/winemetal.dll"
test -f "$STAGE/aarch64-unix/winemetal.so"
file "$STAGE/aarch64-unix/winemetal.so" | grep -q 'Mach-O.*arm64'
"$LLVM_MINGW/bin/llvm-readobj" --file-headers "$STAGE/aarch64-windows/winemetal.dll" | grep -q 'COFF-ARM64EC'

"$LLVM_MINGW/bin/x86_64-w64-mingw32-gcc" -O2 -Wall -Wextra -o "$PROBE" "$VKMT/test/dxmt_arm64_probe.c"
pkill -9 wineserver 2>/dev/null || true
DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib \
WINEDLLPATH="$STAGE" WINEDLLOVERRIDES='winemetal=b' WINEPREFIX="$PREFIX" WINEDEBUG=+loaddll \
  "$VKMT/wine/build-ec/wine" "$PROBE" >"$LOG" 2>&1
grep -q 'DXMT ARM64EC DLLs and arm64 winemetal.so loaded successfully' "$LOG"
grep -q 'winemetal.dll.*builtin' "$LOG"
echo "DXMT ARM64EC/arm64 probe passed; log: $LOG"
