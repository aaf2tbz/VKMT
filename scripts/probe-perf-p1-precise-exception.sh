#!/bin/bash
# Prove exact x64 architectural state at a synchronous multiblock JIT fault.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
RUNS="$VKMT/build/probe-runs"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"

mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/perf-p1-precise.XXXXXX")"
prefix="$run_root/prefix"
status=1
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=5s "${VKMT_P1_TIMEOUT:-30}s")
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=5s "${VKMT_P1_TIMEOUT:-30}s")
fi

cleanup()
{
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  if test -n "${VKMT_P1_EVIDENCE_DIR:-}"; then
    case "$VKMT_P1_EVIDENCE_DIR" in
      "$VKMT"/*)
        mkdir -p "$VKMT_P1_EVIDENCE_DIR"
        find "$run_root" -maxdepth 1 -type f -exec cp {} "$VKMT_P1_EVIDENCE_DIR"/ \;
        printf 'status=%s\n' "$status" >"$VKMT_P1_EVIDENCE_DIR/status.txt"
        ;;
    esac
  fi
  case "$run_root" in "$RUNS"/*) find "$run_root" -depth -delete 2>/dev/null || true ;; esac
}
trap cleanup EXIT

"$TOOL/x86_64-w64-mingw32-clang" -O2 -g -funwind-tables \
  "$VKMT/test/perf/p1_precise_exception.c" \
  "$VKMT/test/perf/p1_precise_exception.s" \
  -o "$run_root/p1-precise.exe"

mkdir -p "$prefix/drive_c/windows/system32"
"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"

run_wine()
{
  "${timeout_cmd[@]}" env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
    WINE_NO_EXPLORER=1 WINEDEBUG="${VKMT_P1_WINEDEBUG:--all}" \
    FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
    FEX_SILENTLOG="${VKMT_P1_FEX_SILENTLOG:-1}" FEX_OUTPUTLOG=stderr \
    FEX_MULTIBLOCK=1 FEX_MAXINST=5000 "$WINE" "$@"
}

run_wine "$WINEBOOT" --init >"$run_root/wineboot.log" 2>&1
"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"

runs="${VKMT_P1_RUNS:-1}"
case "$runs" in *[!0-9]*|'') echo "VKMT_P1_RUNS must be a positive integer" >&2; exit 2 ;; esac
test "$runs" -gt 0 || { echo "VKMT_P1_RUNS must be a positive integer" >&2; exit 2; }
: >"$run_root/precise.log"
for ((run = 1; run <= runs; run++)); do
  run_wine "$run_root/p1-precise.exe" >>"$run_root/precise.log" 2>&1
done
test "$(grep -c '^P1_PRECISE_MULTIBLOCK_OK' "$run_root/precise.log")" -eq "$runs"
status=0
echo P1_PRECISE_MULTIBLOCK_OK
