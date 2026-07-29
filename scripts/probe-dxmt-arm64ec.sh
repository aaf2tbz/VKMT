#!/bin/bash
# Focused native-host DXMT gate.  The Windows probe is ARM64EC; its Unix
# library is ARM64 Mach-O.  i386 and x86_64 Unix libraries are out of scope.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
LLVM_MINGW="${LLVM_MINGW:-$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal}"
STAGE="$BUILD/dxmt-v0.80"
RUNS_DIR="$VKMT/build/probe-runs"
mkdir -p "$RUNS_DIR"
RUN_ROOT="$(mktemp -d "$RUNS_DIR/dxmt-arm64ec.XXXXXX")"
PREFIX="$RUN_ROOT/prefix"
LOG="$RUN_ROOT/probe.log"

cleanup()
{
    WINEPREFIX="$PREFIX" "$WINESERVER" -k >/dev/null 2>&1 || true
    WINEPREFIX="$PREFIX" "$WINESERVER" -w >/dev/null 2>&1 || true
    local live
    live="$(lsof -t +D "$RUN_ROOT" 2>/dev/null || true)"
    if [ -n "$live" ]; then
        printf 'refusing to remove live disposable root %s (pids: %s)\n' "$RUN_ROOT" "$live" >&2
        return
    fi
    find "$RUN_ROOT" -depth -delete
}
trap cleanup EXIT

test -x "$WINE"
test -x "$WINESERVER"
test -x "$WINEBOOT"
test -f "$STAGE/aarch64-windows/winemetal.dll"
test -f "$STAGE/aarch64-unix/winemetal.so"
test -f "$STAGE/aarch64-unix/libunwind.1.dylib"
file "$STAGE/aarch64-unix/winemetal.so" | grep -q 'Mach-O.*arm64'
otool -L "$STAGE/aarch64-unix/winemetal.so" | grep -q '@loader_path/libunwind.1.dylib'
"$LLVM_MINGW/bin/llvm-readobj" --file-headers "$STAGE/aarch64-windows/winemetal.dll" |
    grep -q 'IMAGE_FILE_MACHINE_ARM64EC'
"$VKMT/scripts/integrate-dxmt-arm64ec-builtins.sh"

"$LLVM_MINGW/bin/arm64ec-w64-mingw32-clang" -O2 -ffixed-x18 -ffixed-x28 \
    -o "$RUN_ROOT/dxmt_arm64ec_probe.exe" "$VKMT/test/dxmt_arm64_probe.c"
"$LLVM_MINGW/bin/arm64ec-w64-mingw32-clang" -O2 -ffixed-x18 -ffixed-x28 \
    -o "$RUN_ROOT/dxmt_dxgi_import_probe.exe" "$VKMT/test/dxmt_dxgi_import_probe.c" -ldxgi -ldxguid
"$LLVM_MINGW/bin/llvm-readobj" --file-headers "$RUN_ROOT/dxmt_arm64ec_probe.exe" |
    grep -q 'IMAGE_FILE_MACHINE_ARM64EC'
"$LLVM_MINGW/bin/llvm-readobj" --file-headers "$RUN_ROOT/dxmt_dxgi_import_probe.exe" |
    grep -q 'IMAGE_FILE_MACHINE_ARM64EC'

"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$PREFIX"
WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 WINE_NO_EXPLORER=1 WINEDEBUG=-all \
    "$WINE" "$WINEBOOT" --init >"$RUN_ROOT/wineboot.log" 2>&1
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$PREFIX"
WINEPREFIX="$PREFIX" "$WINESERVER" -k
WINEPREFIX="$PREFIX" "$WINESERVER" -w
ln -sfn "$STAGE/aarch64-windows/winemetal.dll" "$PREFIX/drive_c/windows/system32/winemetal.dll"
ln -sfn "$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll" "$PREFIX/drive_c/windows/system32/xtajit64.dll"

WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 WINEDLLPATH="$STAGE" \
WINEDLLOVERRIDES='winemetal=b' VKMT_DXMT_WMT_ONLY=1 WINEDEBUG=-all DYLD_PRINT_LIBRARIES=1 \
    "$WINE" "$RUN_ROOT/dxmt_arm64ec_probe.exe" >"$LOG" 2>&1
grep -q 'DXMT ARM64EC winemetal.dll / native arm64 bridge passed' "$LOG"
grep -q "$STAGE/aarch64-unix/winemetal.so" "$LOG"
grep -q "$STAGE/aarch64-unix/winemac.so" "$LOG"
WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 WINE_NO_EXPLORER=1 \
WINEDLLOVERRIDES='dxgi,winemetal=b' DXMT_DXGI_FACTORY_RELEASE_ONLY=1 WINEDEBUG=-all \
    "$WINE" "$RUN_ROOT/dxmt_dxgi_import_probe.exe" >>"$LOG" 2>&1
grep -q 'DXMT_ARM64EC_DXGI_IMPORT_FACTORY_RELEASE_OK' "$LOG"
printf 'P1_ARM64EC_DXMT_WMT_OK\n'
printf 'P1_ARM64EC_DXMT_DXGI_FACTORY_OK\n'
