#!/bin/bash
# Phase 1.0: native AArch64 Wine prefix and clean-exit acceptance.
set -eu

VKMT=${VKMT:-/Volumes/AverySSD/VKMT}
BUILD=$VKMT/wine/build-ec
TOOLCHAIN=$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal
RUNS=$VKMT/build/probe-runs
RESULTS=$VKMT/docs/validation

WINE=$BUILD/wine
WINESERVER=$BUILD/server/wineserver
WINEBOOT=$BUILD/programs/wineboot/aarch64-windows/wineboot.exe
SOURCE=$VKMT/test/aarch64_smoke.c

for required in "$WINE" "$WINESERVER" "$WINEBOOT" "$SOURCE" \
                "$TOOLCHAIN/bin/aarch64-w64-mingw32-clang"; do
    test -e "$required" || { echo "missing required path: $required" >&2; exit 1; }
done

mkdir -p "$RUNS" "$RESULTS"
run_root=$(mktemp -d "$RUNS/p1-aarch64-prefix.XXXXXX")
prefix=$run_root/prefix
probe=$run_root/aarch64_smoke.exe
log=$run_root/run.log
summary=$RESULTS/p1-aarch64-prefix.latest

cleanup()
{
    WINEPREFIX="$prefix" "$WINESERVER" -w >>"$log" 2>&1 || true
    if ps -axo args= | grep -F "$prefix" | grep -v grep >/dev/null; then
        echo "FAIL: process still references disposable prefix" >>"$log"
        return 1
    fi
    case "$run_root" in "$RUNS"/*) find "$run_root" -depth -delete ;; *) return 1 ;; esac
}

set +e
(
    echo "phase=P1.0 architecture=aarch64"
    file "$WINE" "$WINESERVER" "$BUILD/dlls/ntdll/ntdll.so"
    PATH="$TOOLCHAIN/bin:$PATH" aarch64-w64-mingw32-clang -O2 -ffixed-x18 -ffixed-x28 \
        -o "$probe" "$SOURCE" || exit $?
    "$TOOLCHAIN/bin/llvm-readobj" --file-headers "$probe" || exit $?
    # Build-tree Wine needs bootstrap mode for an explicit wineboot.exe launch;
    # this gives its PE loader access to the in-tree builtin DLLs before the
    # prefix's system32 links exist.
    "$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix" || exit $?
    WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 WINEDEBUG=-all \
        "$WINE" "$WINEBOOT" --init || exit $?
    "$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix" || exit $?
    WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 WINEDEBUG=-all \
        "$WINE" "$probe" || exit $?
    # wineboot starts background services; close only this disposable server,
    # then prove that it has exited before deleting the run root.
    WINEPREFIX="$prefix" "$WINESERVER" -k || exit $?
    WINEPREFIX="$prefix" "$WINESERVER" -w || exit $?
    echo "P1_AARCH64_PREFIX_OK"
) >"$log" 2>&1
run_status=$?
set -e

if test "$run_status" -ne 0; then
    cat "$log" >&2
    cleanup || true
    exit 1
fi

grep -q 'Machine: IMAGE_FILE_MACHINE_ARM64' "$log"
grep -q 'VKMT native AArch64 smoke passed' "$log"
grep -q 'P1_AARCH64_PREFIX_OK' "$log"

{
    echo "P1.0 native AArch64 prefix acceptance"
    echo "result=PASS"
    grep -E 'Mach-O 64-bit (executable|dynamically linked shared library) arm64|Machine: IMAGE_FILE_MACHINE_ARM64|VKMT native AArch64 smoke passed|P1_AARCH64_PREFIX_OK' "$log"
} >"$summary"
cat "$summary"
cleanup
