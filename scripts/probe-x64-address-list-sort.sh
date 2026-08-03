#!/bin/bash
# Prove the x64 WSAIoctl(SIO_ADDRESS_LIST_SORT) contract in a fresh prefix.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${VKMT_WINE_BUILD:-$VKMT/wine/build-ec}"
TOOLCHAIN="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
RUNS="${VKMT_PROBE_RUNS:-$VKMT/build/probe-runs}"
EVIDENCE="${VKMT_ADDRESS_SORT_EVIDENCE_DIR:-$VKMT/build/address-list-sort/latest}"
prepared_prefix=
fresh=0

usage()
{
    echo "usage: $0 [--prefix PATH | --fresh] [--evidence-dir PATH]" >&2
    exit 2
}

while test "$#" -gt 0; do
    case "$1" in
        --prefix)
            test "$#" -ge 2 || usage
            test -z "$prepared_prefix" || usage
            test "$fresh" = 0 || usage
            prepared_prefix=$2
            shift 2
            ;;
        --fresh)
            test -z "$prepared_prefix" || usage
            fresh=1
            shift
            ;;
        --evidence-dir)
            test "$#" -ge 2 || usage
            EVIDENCE=$2
            shift 2
            ;;
        *) usage ;;
    esac
done
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
XTAJIT64="${VKMT_XTAJIT64_SOURCE:-$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll}"

mkdir -p "$RUNS" "$EVIDENCE"
run_root="$(mktemp -d "$RUNS/x64-address-sort.XXXXXX")"
prefix="${prepared_prefix:-$run_root/prefix}"

cleanup()
{
    status=$?
    WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
    WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
    find "$run_root" -maxdepth 1 -type f -name '*.log' -exec cp -p {} "$EVIDENCE/" \;
    if test -n "$prepared_prefix" && test -f "$prefix/.vkmt/receipt.json"; then
        cp -p "$prefix/.vkmt/receipt.json" "$EVIDENCE/prefix-receipt.json"
    fi
    {
        printf 'prepared_prefix=%s\n' "${prepared_prefix:-fresh}"
        printf 'prefix=%s\n' "$prefix"
        printf 'FEX_TSOENABLED=0\nFEX_VECTORTSOENABLED=0\nFEX_MEMCPYSETTSOENABLED=0\n'
    } >"$EVIDENCE/environment.txt"
    printf 'status=%s\n' "$status" >"$EVIDENCE/status.txt"
    case "$run_root" in "$RUNS"/*) find "$run_root" -depth -delete 2>/dev/null || true ;; esac
    exit "$status"
}
trap cleanup EXIT

"$TOOLCHAIN/x86_64-w64-mingw32-clang" -O2 \
    -o "$run_root/address-list-sort.exe" \
    "$VKMT/test/x64emu/address_list_sort.c" -lws2_32

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
    env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
        WINE_NO_EXPLORER=1 WINEDEBUG="${VKMT_ADDRESS_SORT_WINEDEBUG:--all}" \
        FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
        gtimeout --signal=TERM --kill-after=5s "$timeout" "$WINE" "$@" \
        >"$log" 2>&1
}

if test -n "$prepared_prefix"; then
    "$VKMT/scripts/vkmt-prefix" verify --prefix "$prefix"
else
    stage_providers
    run_wine "$run_root/wineboot.log" "${VKMT_ADDRESS_SORT_BOOT_TIMEOUT:-120}s" \
        "$WINEBOOT" --init
    WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
    WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
    stage_providers
fi
run_wine "$run_root/address-list-sort.log" \
    "${VKMT_ADDRESS_SORT_TIMEOUT:-30}s" "$run_root/address-list-sort.exe"
grep -q '^VKMT_ADDRESS_LIST_SORT_OK' "$run_root/address-list-sort.log"
echo VKMT_X64_ADDRESS_LIST_SORT_OK
