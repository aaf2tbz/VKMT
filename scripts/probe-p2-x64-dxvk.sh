#!/usr/bin/env bash
# Phase 2 acceptance: x86_64 guest -> native ARM64 Wine -> DXVK -> MoltenVK.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${WINEBUILDDIR:-$VKMT/wine/build-ec}"
LLVM_MINGW="${LLVM_MINGW:-$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal}"
DXVK="${DXVK_STAGE:-$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/arm64ec}"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
RUNS_DIR="$VKMT/build/probe-runs"

mkdir -p "$RUNS_DIR"
RUN_ROOT="$(mktemp -d "$RUNS_DIR/p2-x64-dxvk.XXXXXX")"
PREFIX="$RUN_ROOT/prefix"
WINE_PID=""
TIMEOUT=()
if command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT=(gtimeout --signal=TERM --kill-after=10s "${VKMT_P2_TIMEOUT:-180}s")
elif command -v timeout >/dev/null 2>&1; then
    TIMEOUT=(timeout --signal=TERM --kill-after=10s "${VKMT_P2_TIMEOUT:-180}s")
fi

cleanup()
{
    local status=$?
    test -z "$WINE_PID" || kill -TERM "$WINE_PID" 2>/dev/null || true
    WINEPREFIX="$PREFIX" "$WINESERVER" -k >/dev/null 2>&1 || true
    WINEPREFIX="$PREFIX" "$WINESERVER" -w >/dev/null 2>&1 || true
    local live
    live="$(lsof -t +D "$RUN_ROOT" 2>/dev/null || true)"
    if [ -n "$live" ]; then
        printf 'refusing to remove live disposable root %s (pids: %s)\n' "$RUN_ROOT" "$live" >&2
        exit "$status"
    fi
    case "$RUN_ROOT" in
        "$RUNS_DIR"/*) find "$RUN_ROOT" -depth -delete ;;
    esac
    exit "$status"
}
trap cleanup EXIT

run_wine()
{
    local output=$1
    shift
    "${TIMEOUT[@]}" env WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" \
        WINEBOOTSTRAPMODE=1 WINE_NO_EXPLORER=1 WINEDEBUG=-all \
        FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 \
        FEX_MEMCPYSETTSOENABLED=0 "$WINE" "$@" >"$output" 2>&1 &
    WINE_PID=$!
    local result
    if wait "$WINE_PID"; then result=0; else result=$?; fi
    WINE_PID=""
    return "$result"
}

test -x "$WINE"
test -x "$WINESERVER"
test -x "$WINEBOOT"
test -f "$DXVK/dxgi.dll"
test -f "$DXVK/d3d11.dll"
file "$WINE" | grep -q 'Mach-O.*arm64'
file "$WINESERVER" | grep -q 'Mach-O.*arm64'

"$LLVM_MINGW/bin/x86_64-w64-mingw32-gcc" -O2 -o "$RUN_ROOT/entry_x64.exe" \
    "$VKMT/test/x64emu/entry_x64.c"
"$LLVM_MINGW/bin/x86_64-w64-mingw32-gcc" -O2 -o "$RUN_ROOT/d3d11_probe.exe" \
    "$VKMT/test/d3d11_probe.c" -ld3d11 -ldxgi

"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$PREFIX"
run_wine "$RUN_ROOT/wineboot.log" "$WINEBOOT" --init
"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$PREFIX"
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$PREFIX"
cp "$DXVK/dxgi.dll" "$DXVK/d3d11.dll" "$PREFIX/drive_c/windows/system32/"

set +e
run_wine "$RUN_ROOT/entry.log" "$RUN_ROOT/entry_x64.exe"
ENTRY_RC=$?
set -e
test "$ENTRY_RC" = 0
grep -q 'VKMT entry_x64: hello from x86-64 guest' "$RUN_ROOT/entry.log"

VK_ICD_FILENAMES="$VKMT/test/vkmt_icd.json" \
WINEDLLOVERRIDES='dxgi,d3d11=n' \
    run_wine "$RUN_ROOT/d3d11.log" "$RUN_ROOT/d3d11_probe.exe"
grep -q 'DXVK: 3.0.2' "$RUN_ROOT/d3d11.log"
grep -q 'Found device: Apple M4' "$RUN_ROOT/d3d11.log"
grep -q 'VKMT_D3D11_PROBE_OK' "$RUN_ROOT/d3d11.log"

printf 'P2_X64_ENTRY_OK\n'
printf 'P2_X64_DXVK_D3D11_READBACK_OK\n'
