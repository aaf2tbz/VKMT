#!/bin/bash
# Isolate the ARM64EC native -> x64 WNDPROC -> native return contract.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_ROOT="${VKMT_RUNTIME_ROOT:-$VKMT}"
BUILD="${VKMT_WINE_BUILD:-$RUNTIME_ROOT/wine/build-ec}"
TOOLCHAIN="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
RUNS="${VKMT_PROBE_RUNS:-$VKMT/build/probe-runs}"
EVIDENCE="${VKMT_WNDPROC_EVIDENCE_DIR:-$VKMT/build/wndproc-callback/latest}"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
XTAJIT64="${VKMT_XTAJIT64_SOURCE:-$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll}"

for input in "$WINE" "$WINESERVER" "$WINEBOOT" "$XTAJIT64" \
             "$VKMT/test/x64emu/wndproc_callback.c"; do
    test -e "$input" || { echo "Missing WNDPROC probe input: $input" >&2; exit 1; }
done

mkdir -p "$RUNS" "$EVIDENCE"
run_root="$(mktemp -d "$RUNS/x64-wndproc.XXXXXX")"
prefix="$run_root/prefix"

cleanup()
{
    status=$?
    WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
    WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
    find "$run_root" -maxdepth 1 -type f -name '*.log' -exec cp -p {} "$EVIDENCE/" \;
    printf 'status=%s\n' "$status" >"$EVIDENCE/status.txt"
    case "$run_root" in "$RUNS"/*) find "$run_root" -depth -delete 2>/dev/null || true ;; esac
    exit "$status"
}
trap cleanup EXIT

"$TOOLCHAIN/x86_64-w64-mingw32-clang" -O2 -o "$run_root/wndproc.exe" \
    "$VKMT/test/x64emu/wndproc_callback.c" -luser32

stage_providers()
{
    mkdir -p "$prefix/drive_c/windows/system32"
    install -m 0644 "$XTAJIT64" "$prefix/drive_c/windows/system32/xtajit64.dll"
    for dll in xtajit wow64 wow64win; do
        install -m 0644 "$BUILD/dlls/$dll/aarch64-windows/$dll.dll" \
            "$prefix/drive_c/windows/system32/$dll.dll"
    done
}

run_wine()
{
    log=$1
    timeout=$2
    shift 2
    env_args=(
        WINEPREFIX="$prefix"
        WINEBUILDDIR="$BUILD"
        WINEBOOTSTRAPMODE=1
        WINEDEBUG="${VKMT_WNDPROC_WINEDEBUG:--all}"
        FEX_TSOENABLED=0
        FEX_VECTORTSOENABLED=0
        FEX_MEMCPYSETTSOENABLED=0
    )
    test "${VKMT_WNDPROC_WINE_NO_EXPLORER:-0}" != 1 || env_args+=(WINE_NO_EXPLORER=1)
    env "${env_args[@]}" \
        gtimeout --signal=TERM --kill-after=5s "$timeout" "$WINE" "$@" \
        >"$log" 2>&1
}

stage_providers
VKMT_WNDPROC_WINEDEBUG=-all run_wine "$run_root/wineboot.log" \
    "${VKMT_WNDPROC_BOOT_TIMEOUT:-120}s" "$WINEBOOT" --init
WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
stage_providers

run_wine "$run_root/wndproc.log" "${VKMT_WNDPROC_TIMEOUT:-30}s" "$run_root/wndproc.exe"
grep -q '^VKMT_WNDPROC_CALLBACK_OK' "$run_root/wndproc.log"
echo VKMT_X64_WNDPROC_CALLBACK_OK
