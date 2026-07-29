#!/bin/bash
# Phase 1 unified native-host acceptance.  One disposable prefix proves the
# ARM64 host, pure-AArch64 VKMT (DXVK/vkd3d/MoltenVK), and ARM64EC DXMT bridge.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
WINE="$BUILD/loader/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
DXVK="$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/aarch64"
VKD3D="$VKMT/third_party/vkd3d-proton/install-arm64/bin"
DXMT="$BUILD/dxmt-v0.80"
RUNS="$VKMT/build/probe-runs"

for required in "$WINE" "$WINESERVER" "$WINEBOOT" \
    "$DXVK/dxgi.dll" "$DXVK/d3d11.dll" \
    "$VKD3D/d3d12.dll" "$VKD3D/d3d12core.dll" \
    "$DXMT/aarch64-windows/winemetal.dll" "$DXMT/aarch64-unix/winemetal.so"; do
    test -e "$required" || { echo "missing required path: $required" >&2; exit 1; }
done

RUN_ROOT="$(mktemp -d "$RUNS/p1-unified-arm64.XXXXXX")"
PREFIX="$RUN_ROOT/prefix"
LOG="$RUN_ROOT/probe.log"

cleanup()
{
    WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" "$WINESERVER" -k >/dev/null 2>&1 || true
    WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" "$WINESERVER" -w >/dev/null 2>&1 || true
    case "$RUN_ROOT" in "$RUNS"/*) find "$RUN_ROOT" -depth -delete ;; *) return 1 ;; esac
}
trap cleanup EXIT

export WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1
export WINE_NO_EXPLORER=1 WINEDEBUG=-all VK_ICD_FILENAMES="$VKMT/test/vkmt_icd.json"

"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$PREFIX"

"$TOOL/aarch64-w64-mingw32-clang" -O2 -ffixed-x18 -ffixed-x28 \
    -o "$RUN_ROOT/aarch64_smoke.exe" "$VKMT/test/aarch64_smoke.c"
"$TOOL/aarch64-w64-mingw32-clang" -O2 -ffixed-x18 -ffixed-x28 \
    -o "$RUN_ROOT/aarch64_d3d11.exe" "$VKMT/test/d3d11_probe.c" -ld3d11 -ldxgi
"$TOOL/aarch64-w64-mingw32-clang" -O2 -ffixed-x18 -ffixed-x28 \
    -o "$RUN_ROOT/aarch64_d3d12.exe" "$VKMT/test/d3d12_probe_nodxgi.c" -ld3d12 -ldxguid
"$TOOL/arm64ec-w64-mingw32-clang" -O2 -ffixed-x18 -ffixed-x28 \
    -o "$RUN_ROOT/dxmt_bridge.exe" "$VKMT/test/dxmt_arm64_probe.c"
"$TOOL/arm64ec-w64-mingw32-clang" -O2 -ffixed-x18 -ffixed-x28 \
    -o "$RUN_ROOT/dxmt_dxgi.exe" "$VKMT/test/dxmt_dxgi_import_probe.c" -ldxgi -ldxguid

"$TOOL/llvm-readobj" --file-headers "$RUN_ROOT/aarch64_d3d11.exe" | grep -q 'IMAGE_FILE_MACHINE_ARM64'
"$TOOL/llvm-readobj" --file-headers "$RUN_ROOT/dxmt_bridge.exe" | grep -q 'IMAGE_FILE_MACHINE_ARM64EC'
file "$WINE" "$WINESERVER" "$BUILD/dlls/ntdll/ntdll.so" | grep -q 'arm64'

"$WINE" "$WINEBOOT" --init >>"$LOG" 2>&1
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$PREFIX"

# Pure AArch64 DXVK and vkd3d-proton form the VKMT route.
cp "$DXVK/dxgi.dll" "$PREFIX/drive_c/windows/system32/dxgi.dll"
cp "$DXVK/d3d11.dll" "$PREFIX/drive_c/windows/system32/d3d11.dll"
cp "$VKD3D/d3d12.dll" "$PREFIX/drive_c/windows/system32/d3d12.dll"
cp "$VKD3D/d3d12core.dll" "$PREFIX/drive_c/windows/system32/d3d12core.dll"

WINEDEBUG=-all WINEDLLOVERRIDES='dxgi,d3d11,d3d12,d3d12core=n' DXVK_LOG_LEVEL=warn \
    "$WINE" "$RUN_ROOT/aarch64_smoke.exe" >>"$LOG" 2>&1
WINEDEBUG=-all WINEDLLOVERRIDES='dxgi,d3d11=n' DXVK_LOG_LEVEL=warn \
    "$WINE" "$RUN_ROOT/aarch64_d3d11.exe" >>"$LOG" 2>&1
WINEDEBUG=-all VKMT_ALLOW_NON_SINGLE_TEXEL_ALIGNMENT=1 WINEDLLOVERRIDES='dxgi,d3d12,d3d12core=n' \
    "$WINE" "$RUN_ROOT/aarch64_d3d12.exe" >>"$LOG" 2>&1

# Switch only the PE D3D11/DXGI pair for the ARM64EC DXMT bridge proof.
cp "$DXMT/aarch64-windows/dxgi.dll" "$PREFIX/drive_c/windows/system32/dxgi.dll"
cp "$DXMT/aarch64-windows/d3d11.dll" "$PREFIX/drive_c/windows/system32/d3d11.dll"
ln -sfn "$DXMT/aarch64-windows/winemetal.dll" "$PREFIX/drive_c/windows/system32/winemetal.dll"
ln -sfn "$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll" "$PREFIX/drive_c/windows/system32/xtajit64.dll"

WINEDEBUG=-all WINEDLLPATH="$DXMT" WINEDLLOVERRIDES='winemetal=b' VKMT_DXMT_WMT_ONLY=1 \
    "$WINE" "$RUN_ROOT/dxmt_bridge.exe" >>"$LOG" 2>&1
WINEDEBUG=-all WINEDLLOVERRIDES='dxgi,winemetal=b' DXMT_DXGI_FACTORY_RELEASE_ONLY=1 \
    "$WINE" "$RUN_ROOT/dxmt_dxgi.exe" >>"$LOG" 2>&1

WINEPREFIX="$PREFIX" "$WINESERVER" -k
WINEPREFIX="$PREFIX" "$WINESERVER" -w

grep -q 'VKMT native AArch64 smoke passed' "$LOG"
grep -q 'VKMT_D3D11_PROBE_OK' "$LOG"
grep -q 'PROBE OK' "$LOG"
grep -q 'DXMT ARM64EC winemetal.dll / native arm64 bridge passed' "$LOG"
grep -q 'DXMT_ARM64EC_DXGI_IMPORT_FACTORY_RELEASE_OK' "$LOG"
printf 'P1_UNIFIED_ARM64_AARCH64_ARM64EC_OK\n'
