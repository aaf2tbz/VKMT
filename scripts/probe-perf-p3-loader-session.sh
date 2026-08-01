#!/bin/bash
# P3 acceptance: retained ARM64 wrapper, resolver probes, and warm-session policy.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
RUNS="$VKMT/build/probe-runs"
PREFIX=
PATH_RUNS="${VKMT_P3_PATH_RUNS:-3}"

usage()
{
  echo "usage: $0 --prefix PREFIX" >&2
  exit 2
}

while test $# -gt 0; do
  case "$1" in
    --prefix) test $# -ge 2 || usage; PREFIX=$2; shift 2 ;;
    *) usage ;;
  esac
done
test -n "$PREFIX" || usage
test -d "$PREFIX" || { echo "Missing prefix: $PREFIX" >&2; exit 1; }
PREFIX="$(cd "$PREFIX" && pwd -P)"
case "$PATH_RUNS" in *[!0-9]*|'') usage ;; esac
test "$PATH_RUNS" -gt 0 || usage

mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/perf-p3-loader.XXXXXX")"
fixture="$run_root/i386-basic.exe"
status=1

stop_server()
{
  WINEPREFIX="$PREFIX" "$BUILD/server/wineserver" -k 2>/dev/null || true
  WINEPREFIX="$PREFIX" "$BUILD/server/wineserver" -w 2>/dev/null || true
}

cleanup()
{
  stop_server
  if test -n "${VKMT_P3_EVIDENCE_DIR:-}"; then
    case "$VKMT_P3_EVIDENCE_DIR" in
      "$VKMT"/*)
        mkdir -p "$VKMT_P3_EVIDENCE_DIR"
        find "$run_root" -maxdepth 1 -type f ! -name '*.exe' -exec cp {} "$VKMT_P3_EVIDENCE_DIR"/ \;
        printf 'status=%s\n' "$status" >"$VKMT_P3_EVIDENCE_DIR/status.txt"
        ;;
    esac
  fi
  case "$run_root" in "$RUNS"/*) find "$run_root" -depth -delete 2>/dev/null || true ;; esac
}
trap cleanup EXIT

test "$(/usr/bin/lipo -archs "$BUILD/wine")" = arm64
test "$(/usr/bin/lipo -archs "$BUILD/server/wineserver")" = arm64
test "$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null || echo 0)" = 0
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$PREFIX"
"$TOOL/i686-w64-mingw32-clang" -O2 -s "$VKMT/test/i386/basic.c" -o "$fixture"

export WINEPREFIX="$PREFIX"
export WINEBUILDDIR="$BUILD"
source "$VKMT/scripts/vkmt-runtime-env.sh"
test "$FEX_ENABLECODECACHINGWIP" = 1
test "$FEX_TSOENABLED:$FEX_VECTORTSOENABLED:$FEX_MEMCPYSETTSOENABLED" = 0:0:0

run_guest()
{
  local log=$1
  shift
  env -u VKMT_FORCE_WINE_REEXEC "$@" \
    WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
    WINE_NO_EXPLORER=1 WINEDEBUG=-all MVK_CONFIG_LOG_LEVEL=0 \
    FEX_ENABLECODECACHINGWIP=1 \
    FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
    DYLD_LIBRARY_PATH="$DYLD_LIBRARY_PATH" GI_TYPELIB_PATH="$GI_TYPELIB_PATH" \
    GST_PLUGIN_PATH_1_0="$GST_PLUGIN_PATH_1_0" \
    GST_PLUGIN_SYSTEM_PATH_1_0="$GST_PLUGIN_SYSTEM_PATH_1_0" \
    GST_PLUGIN_SCANNER_1_0="$GST_PLUGIN_SCANNER_1_0" GST_REGISTRY="$GST_REGISTRY" \
    "$BUILD/wine" "$fixture" >"$log" 2>&1
  grep -Fq 'VKMT i386 basic passed' "$log"
}

printf 'mode\trun\tinitial_find\tinitial_miss\n' >"$run_root/path-probes.tsv"
for mode in historical_reexec retained_wrapper; do
  for run in $(seq 1 "$PATH_RUNS"); do
    stop_server
    log="$run_root/$mode-$run.log"
    if test "$mode" = historical_reexec; then
      run_guest "$log" VKMT_FORCE_WINE_REEXEC=1 DYLD_PRINT_SEARCHING=1
    else
      run_guest "$log" DYLD_PRINT_SEARCHING=1
    fi
    pid="$(sed -nE '/^dyld\[[0-9]+\]:/{s/^dyld\[([0-9]+)\]:.*/\1/p;q;}' "$log")"
    test -n "$pid"
    finds="$(awk -v p="dyld[$pid]:" 'index($0,p)==1 && /find path / {n++} END {print n+0}' "$log")"
    misses="$(awk -v p="dyld[$pid]:" 'index($0,p)==1 && /not found:/ {n++} END {print n+0}' "$log")"
    printf '%s\t%s\t%s\t%s\n' "$mode" "$run" "$finds" "$misses" >>"$run_root/path-probes.tsv"
    if test "$mode" = retained_wrapper; then
      ! grep -Eq '/opt/homebrew|/Homebrew/Cellar|/usr/local/' "$log"
    fi
  done
done

old_min="$(awk -F '\t' '$1 == "historical_reexec" {if (!n++ || $4 < v) v=$4} END {print v+0}' "$run_root/path-probes.tsv")"
new_max="$(awk -F '\t' '$1 == "retained_wrapper" {if (!n++ || $4 > v) v=$4} END {print v+0}' "$run_root/path-probes.tsv")"
test "$old_min" -gt 0
test $((new_max * 2)) -le "$old_min" || {
  echo "Failed path probes did not fall by at least 50%: old_min=$old_min new_max=$new_max" >&2
  exit 1
}

stop_server
"$VKMT/scripts/vkmt-warm-session.sh" start --prefix "$PREFIX" --reason p3-loader-probe >/dev/null
run_guest "$run_root/warm-primer.log"
env -u VKMT_FORCE_WINE_REEXEC \
  WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
  WINE_NO_EXPLORER=1 WINEDEBUG=+module MVK_CONFIG_LOG_LEVEL=0 \
  FEX_ENABLECODECACHINGWIP=1 \
  FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
  DYLD_LIBRARY_PATH="$DYLD_LIBRARY_PATH" "$BUILD/wine" "$fixture" >"$run_root/resolver.log" 2>&1
grep -Fq 'VKMT i386 basic passed' "$run_root/resolver.log"
failed_builtin="$(rg 'builtin path probe ' "$run_root/resolver.log" | rg -c 'ffffffffc000000f' || true)"
test "${failed_builtin:-0}" = 0
test "$(rg 'find_builtin_dll looking for ' "$run_root/resolver.log" | rg -c 'tzres' || true)" -le 2
! grep -q 'cannot find builtin library.*xtajit' "$run_root/resolver.log"

"$VKMT/scripts/vkmt-warm-session.sh" verify --prefix "$PREFIX" >"$run_root/warm-session.log"
"$VKMT/scripts/vkmt-warm-session.sh" stop --prefix "$PREFIX" --reason p3-loader-probe >>"$run_root/warm-session.log"
cat "$run_root/path-probes.tsv"
printf 'P3_PATH_PROBE_REDUCTION_OK old_min=%s new_max=%s reduction_pct=%.2f\n' \
  "$old_min" "$new_max" "$(awk -v old="$old_min" -v new="$new_max" 'BEGIN {print (old-new)*100/old}')"
echo P3_RESOLVER_CACHE_OK
echo P3_WARM_SESSION_OK
status=0
echo P3_LOADER_SESSION_ACCEPTANCE_OK
