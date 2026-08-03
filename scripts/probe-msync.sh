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
prepared_prefix=
while test "$#" -gt 0; do
    case "$1" in
        --prefix) test "$#" -ge 2 || { echo "--prefix needs a path" >&2; exit 2; }; prepared_prefix=$2; shift 2 ;;
        --fresh) test -z "$prepared_prefix" || { echo "--fresh conflicts with --prefix" >&2; exit 2; }; shift ;;
        --evidence-dir) test "$#" -ge 2 || { echo "--evidence-dir needs a path" >&2; exit 2; }; RESULTS=$2; shift 2 ;;
        *) echo "usage: $0 [--fresh | --prefix PATH] [--evidence-dir PATH]" >&2; exit 2 ;;
    esac
done

mkdir -p "$RUNS" "$RESULTS"
run_root=$(mktemp -d "$RUNS/msync.XXXXXX")
prefix="${prepared_prefix:-$run_root/prefix}"
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
    if test -f "$prefix/.vkmt/receipt.json"; then
        cp "$prefix/.vkmt/receipt.json" "$RESULTS/prefix-receipt.json"
    fi
    {
        printf 'prepared_prefix=%s\n' "$prepared_prefix"
        printf 'host_arch=%s\n' "$(uname -m)"
        printf 'FEX_TSOENABLED=%s\n' "${FEX_TSOENABLED:-0}"
        printf 'FEX_VECTORTSOENABLED=%s\n' "${FEX_VECTORTSOENABLED:-0}"
        printf 'FEX_MEMCPYSETTSOENABLED=%s\n' "${FEX_MEMCPYSETTSOENABLED:-0}"
        printf 'status=%s\n' "$status"
    } >"$RESULTS/environment.txt"
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

if test -n "$prepared_prefix"; then
    "$VKMT/scripts/vkmt-prefix" verify --prefix "$prefix"
else
    "$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
    WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 WINEDEBUG=-all \
        "$WINE" "$WINEBOOT" --init >>"$log" 2>&1
    "$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"
fi
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

wait_for_marker()
{
    marker=$1
    i=0
    while test ! -s "$marker" && test "$i" -lt 1000; do
        sleep 0.01
        i=$((i + 1))
    done
    test -s "$marker"
}

run_pulse_probe()
{
    mode=$1
    marker="$run_root/pulse-${mode}.ready"
    marker_win="Z:${marker}"

    echo "mode=pulse-${mode}" >>"$log"
    VKMT_MSYNC_TEST_REGISTER_FILE="$marker" WINEMSYNC=1 WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" \
        WINEBOOTSTRAPMODE=1 WINEDEBUG=-all "$WINE" "$probe" --pulse-local "$mode" "$marker_win" >>"$log" 2>&1
    grep -q "^MSYNC_PULSE_LOCAL_OK mode=${mode}" "$log"
    stop_server
}

run_waitall_rollback_probe()
{
    ready="$run_root/waitall.ready"
    release="$run_root/waitall.release"
    ready_win="Z:${ready}"
    release_win="Z:${release}"

    echo "mode=forced-waitall-rollback" >>"$log"
    VKMT_MSYNC_TEST_WAITALL_READY_FILE="$ready" VKMT_MSYNC_TEST_WAITALL_RELEASE_FILE="$release" \
        WINEMSYNC=1 WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 WINEDEBUG=-all \
        "$WINE" "$probe" --waitall-rollback-local "$ready_win" "$release_win" >>"$log" 2>&1
    grep -q '^MSYNC_WAITALL_ROLLBACK_LOCAL_OK' "$log"
    stop_server
}

run_pulse_probe manual
run_pulse_probe auto
run_waitall_rollback_probe

echo "mode=stale-port-recovery" >>"$log"
VKMT_MSYNC_TEST_STALE_PORT_ONCE=1 WINEMSYNC=1 WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" \
    WINEBOOTSTRAPMODE=1 WINEDEBUG=-all "$WINE" "$probe" >>"$log" 2>&1
stop_server

stale_recovery_count=$(grep -c '^VKMT_MSYNC_STALE_PORT_RECOVERED' "$log")
test "$stale_recovery_count" -ge 1
test "$stale_recovery_count" -le 16
test "$(grep -c 'falling back to bounded ulock waits' "$log" || true)" -eq 0

echo "mode=invalid-destination-fallback" >>"$log"
VKMT_MSYNC_TEST_INVALID_DEST=1 WINEMSYNC=1 WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" \
    WINEBOOTSTRAPMODE=1 WINEDEBUG=err+sync "$WINE" "$probe" >>"$log" 2>&1
stop_server

test "$(grep -c '^MSYNC_SYNC_OK' "$log")" -eq 5
grep -q '^msync: bootstrapped mach port ' "$log"
grep -q '^msync: up and running\.$' "$log"
test "$(grep -c '^msync: up and running\.$' "$log")" -eq 6
fallback_count=$(grep -c 'Failed to send server register wait: 0x10000003; falling back to bounded ulock waits' "$log")
fallback_processes=$(grep 'Failed to send server register wait: 0x10000003; falling back to bounded ulock waits' "$log" |
    sed -E 's/^([0-9a-f]+):.*/\1/' | sort -u | wc -l | tr -d ' ')
test "$fallback_count" -ge 1
test "$fallback_count" -eq "$fallback_processes"
test "$fallback_count" -le 16

{
    echo "MSync toggle acceptance"
    echo "result=PASS"
    echo "default=PASS"
    echo "explicit_off=PASS"
    echo "enabled=PASS"
    echo "stale_port_recovery=PASS"
    echo "stale_port_recoveries=$stale_recovery_count"
    echo "invalid_destination_fallback=PASS"
    echo "invalid_destination_diagnostics=$fallback_count"
    echo "invalid_destination_processes=$fallback_processes"
    echo "pulse_manual=PASS"
    echo "pulse_auto=PASS"
    echo "forced_waitall_rollback=PASS"
    grep -E '^msync: (bootstrapped|up and running)|^MSYNC_(CHILD|SYNC)_OK|^MSYNC_PULSE_LOCAL_OK|^MSYNC_WAITALL_ROLLBACK_LOCAL_OK|^VKMT_MSYNC_STALE_PORT_RECOVERED' "$log" |
        tr -d '\r' |
        sed -E 's/^(msync: bootstrapped mach port on ).*-msync\.$/\1<prefix>-msync./'
} >"$summary"
cat "$summary"
