#!/bin/bash
# Build and run the M6.0 i386 guest-execution smoke test under native ARM64 Wine.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
LLVM_MINGW="${LLVM_MINGW:-/Volumes/AverySSD/toolchains/llvm-mingw-20260616-ucrt-macos-universal}"
WINE_BUILD="$VKMT/wine/build-ec"
PROBE="$VKMT/test/i386_smoke.exe"
XTAJIT="$WINE_BUILD/dlls/xtajit/aarch64-windows/xtajit.dll"

test -x "$WINE_BUILD/wine" || { echo "Missing native Wine build" >&2; exit 1; }
test -f "$XTAJIT" || { echo "Missing FEX xtajit.dll; run scripts/build-fex-wow64.sh" >&2; exit 1; }

export PATH="$LLVM_MINGW/bin:$PATH"
i686-w64-mingw32-gcc -O2 -Wall -Wextra "$VKMT/test/i386_smoke.c" -o "$PROBE"

machine="$($LLVM_MINGW/bin/llvm-readobj --file-headers "$PROBE" | awk '/Machine:/ {print $2; exit}')"
test "$machine" = "IMAGE_FILE_MACHINE_I386" || {
  echo "Probe is not i386: $machine" >&2
  exit 1
}

prefix="$(mktemp -d /tmp/vkmt-i386-prefix.XXXXXX)"
cleanup() {
  pkill -9 wineserver 2>/dev/null || true
  rm -rf "$prefix"
}
trap cleanup EXIT

echo "i386 probe: $PROBE"
echo "xtajit: $XTAJIT"
log="$(mktemp /tmp/vkmt-i386-probe.XXXXXX)"
trap 'rm -f "$log"; cleanup' EXIT
WINEPREFIX="$prefix" DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib \
  WINEDEBUG=+loaddll "$WINE_BUILD/wine" "$PROBE" >"$log" 2>&1 || {
    echo "Wine rejected the i386 process before guest execution" >&2
    rg -i 'xtajit|sub-4gb|out of memory|failed to load' "$log" >&2 || true
    exit 1
  }

if ! rg -F 'VKMT i386 WoW64 smoke passed' "$log"; then
  echo "i386 guest code did not execute" >&2
  rg -i 'xtajit|sub-4gb|out of memory|failed to load' "$log" >&2 || true
  exit 1
fi

rg -i 'xtajit|VKMT i386 WoW64 smoke passed' "$log"
