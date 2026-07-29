#!/bin/bash
# Prove the default wineserver path and the opt-in macOS MSync path.
set -eu

VKMT=${VKMT:-/Volumes/AverySSD/VKMT}
BUILD=$VKMT/wine/build-ec
TOOLCHAIN=$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal
RUNS=$VKMT/build/probe-runs
RESULTS=$VKMT/docs/validation
WINE=$BUILD/wine
WINESERVER=$BUILD/server/wineserver
WINEBOOT=$BUILD/programs/wineboot/aarch64-windows/wineboot.exe

mkdir -p "$RUNS" "$RESULTS"
run_root=$(mktemp -d "$RUNS/msync.XXXXXX")
prefix=$run_root/prefix
probe=$run_root/msync_sync.exe
log=$run_root/run.log
summary=$RESULTS/msync.latest

stop_server()
{
    WINEPREFIX="$prefix" "$WINESERVER" -k >>"$log" 2>&1 || true
    WINEPREFIX="$prefix" "$WINESERVER" -w >>"$log" 2>&1 || true
}

cleanup()
{
    stop_server
    if ps -axo args= | grep -F "$prefix" | grep -v grep >/dev/null; then
        echo "FAIL: process still references disposable prefix" >>"$log"
        return 1
    fi
    case "$run_root" in "$RUNS"/*) find "$run_root" -depth -delete ;; *) return 1 ;; esac
}

finish()
{
    status=$?
    if test "$status" -ne 0 && test -f "$log"; then
        cp "$log" "$RESULTS/msync.failed.log"
        cat "$log" >&2
    fi
    cleanup || true
    exit "$status"
}
trap finish EXIT

PATH="$TOOLCHAIN/bin:$PATH" aarch64-w64-mingw32-clang -O2 -ffixed-x18 -ffixed-x28 \
    -municode -o "$probe" "$VKMT/test/msync_sync.c"

"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 WINEDEBUG=-all \
    "$WINE" "$WINEBOOT" --init >>"$log" 2>&1
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"
stop_server

echo "mode=default" >>"$log"
env -u WINEMSYNC WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 WINEDEBUG=-all \
    "$WINE" "$probe" >>"$log" 2>&1
stop_server

echo "mode=explicit-off" >>"$log"
WINEMSYNC=0 WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 WINEDEBUG=-all \
    "$WINE" "$probe" >>"$log" 2>&1
stop_server

echo "mode=enabled" >>"$log"
WINEMSYNC=1 WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 WINEDEBUG=-all \
    "$WINE" "$probe" >>"$log" 2>&1
stop_server

test "$(grep -c '^MSYNC_SYNC_OK' "$log")" -eq 3
grep -q '^msync: bootstrapped mach port ' "$log"
grep -q '^msync: up and running\.$' "$log"
test "$(grep -c '^msync: up and running\.$' "$log")" -eq 1

{
    echo "MSync toggle acceptance"
    echo "result=PASS"
    echo "default=PASS"
    echo "explicit_off=PASS"
    echo "enabled=PASS"
    grep -E '^msync: (bootstrapped|up and running)|^MSYNC_(CHILD|SYNC)_OK' "$log" |
        tr -d '\r' |
        sed -E 's/^(msync: bootstrapped mach port on ).*-msync\.$/\1<prefix>-msync./'
} >"$summary"
cat "$summary"
