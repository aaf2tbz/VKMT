#!/bin/bash
# Prove Chromium's nonblocking IPv6 connect/read event pattern through x64 FEX.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${VKMT_WINE_BUILD:-$VKMT/wine/build-ec}"
TOOLCHAIN="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
RUNS="${VKMT_PROBE_RUNS:-$VKMT/build/probe-runs}"
EVIDENCE="${VKMT_IPV6_EVIDENCE_DIR:-$VKMT/build/ipv6-event-connect/latest}"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
XTAJIT64="${VKMT_XTAJIT64_SOURCE:-$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll}"

mkdir -p "$RUNS" "$EVIDENCE"
run_root="$(mktemp -d "$RUNS/x64-ipv6-connect.XXXXXX")"
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

"$TOOLCHAIN/x86_64-w64-mingw32-clang" -O2 -o "$run_root/ipv6-event-connect.exe" \
    "$VKMT/test/x64emu/ipv6_event_connect.c" -lws2_32
"$TOOLCHAIN/x86_64-w64-mingw32-clang" -O2 -o "$run_root/event-connect-parallel.exe" \
    "$VKMT/test/x64emu/event_connect_parallel.c" -lws2_32
"$TOOLCHAIN/x86_64-w64-mingw32-clang" -O2 -o "$run_root/event-read-rearm.exe" \
    "$VKMT/test/x64emu/event_read_rearm.c" -lws2_32

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
    log=$1 timeout=$2
    shift 2
    env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
        WINE_NO_EXPLORER=1 WINEDEBUG="${VKMT_IPV6_WINEDEBUG:--all}" \
        FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
        gtimeout --signal=TERM --kill-after=5s "$timeout" "$WINE" "$@" >"$log" 2>&1
}

stage_providers
run_wine "$run_root/wineboot.log" "${VKMT_IPV6_BOOT_TIMEOUT:-120}s" "$WINEBOOT" --init
WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
stage_providers
run_wine "$run_root/ipv6-event-connect.log" "${VKMT_IPV6_TIMEOUT:-30}s" \
    "$run_root/ipv6-event-connect.exe" "${VKMT_IPV6_ADDRESS:-2606:4700:10::ac42:93f3}"
grep -q '^VKMT_IPV6_EVENT_CONNECT_OK' "$run_root/ipv6-event-connect.log"
run_wine "$run_root/event-connect-parallel-ipv4.log" "${VKMT_IPV6_TIMEOUT:-30}s" \
    "$run_root/event-connect-parallel.exe" "${VKMT_IPV4_ADDRESS:-104.20.23.154}"
grep -q '^VKMT_PARALLEL_EVENT_CONNECT_OK' "$run_root/event-connect-parallel-ipv4.log"
run_wine "$run_root/event-connect-parallel-ipv6.log" "${VKMT_IPV6_TIMEOUT:-30}s" \
    "$run_root/event-connect-parallel.exe" "${VKMT_IPV6_ADDRESS:-2606:4700:10::ac42:93f3}"
grep -q '^VKMT_PARALLEL_EVENT_CONNECT_OK' "$run_root/event-connect-parallel-ipv6.log"
python3 -c 'import socket,time; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind(("127.0.0.1",19446)); s.listen(1); c,_=s.accept(); time.sleep(.2); c.sendall(b"AB"); time.sleep(1); c.close(); s.close()' \
    >"$run_root/rearm-server.log" 2>&1 &
server_pid=$!
run_wine "$run_root/event-read-rearm.log" "${VKMT_IPV6_TIMEOUT:-30}s" \
    "$run_root/event-read-rearm.exe"
wait "$server_pid"
grep -q '^VKMT_EVENT_READ_REARM_OK' "$run_root/event-read-rearm.log"
echo VKMT_X64_IPV6_EVENT_CONNECT_OK
