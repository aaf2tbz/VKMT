#!/bin/bash
# P0 Wine/FEX startup benchmark: four cache/session states with strict rc=0.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
EXEC_RUNNER="$VKMT/build/tools/vkmt-perf-exec"
RUNS=20
SESSIONS=2
ARCH=x86_64
PREFIX=
FIXTURE=
OUTPUT=
EXPECT_OUTPUT=
GATE_STATES=all
STATES=all
CODE_CACHE=0

usage()
{
  echo "usage: $0 --prefix PREFIX [--arch x86_64|i386] [--fixture EXE] [--expect-output TEXT] [--runs N] [--sessions N] [--states all|STATE,...] [--gate-states all|STATE,...] [--code-cache 0|1] [--output DIR]" >&2
  exit 2
}

while test $# -gt 0; do
  case "$1" in
    --prefix) test $# -ge 2 || usage; PREFIX=$2; shift 2 ;;
    --arch) test $# -ge 2 || usage; ARCH=$2; shift 2 ;;
    --fixture) test $# -ge 2 || usage; FIXTURE=$2; shift 2 ;;
    --expect-output) test $# -ge 2 || usage; EXPECT_OUTPUT=$2; shift 2 ;;
    --gate-states) test $# -ge 2 || usage; GATE_STATES=$2; shift 2 ;;
    --states) test $# -ge 2 || usage; STATES=$2; shift 2 ;;
    --code-cache) test $# -ge 2 || usage; CODE_CACHE=$2; shift 2 ;;
    --runs) test $# -ge 2 || usage; RUNS=$2; shift 2 ;;
    --sessions) test $# -ge 2 || usage; SESSIONS=$2; shift 2 ;;
    --output) test $# -ge 2 || usage; OUTPUT=$2; shift 2 ;;
    *) usage ;;
  esac
done

test -n "$PREFIX" || usage
case "$ARCH" in x86_64|i386) ;; *) usage ;; esac
case "$RUNS:$SESSIONS" in *[!0-9:]*|0:*|*:0) usage ;; esac
case "$CODE_CACHE" in 0|1) ;; *) usage ;; esac
validate_states()
{
  local value=$1 state old_ifs
  case ",$value," in
    *,all,*) return 0 ;;
  esac
    old_ifs=$IFS
    IFS=,
    for state in $value; do
      case "$state" in
        cold_process_cold_server|warm_files_cold_server|persistent_server|persistent_session_warm_guest) ;;
        *) usage ;;
      esac
    done
    IFS=$old_ifs
}
validate_states "$STATES"
validate_states "$GATE_STATES"
test "$STATES" != all || STATES=cold_process_cold_server,warm_files_cold_server,persistent_server,persistent_session_warm_guest
test -d "$PREFIX" || { echo "Missing prefix: $PREFIX" >&2; exit 1; }
test -x "$WINE" && test -x "$WINESERVER" || { echo "Missing Wine runtime" >&2; exit 1; }
test "$(/usr/bin/lipo -archs "$WINE")" = arm64 || { echo "Wine host is not ARM64" >&2; exit 1; }
translated=$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null || echo 0)
test "$translated" = 0 || { echo "Benchmark runner is under Rosetta" >&2; exit 1; }

if test -z "$FIXTURE"; then
  run_root=$(dirname "$PREFIX")
  FIXTURE="$run_root/$ARCH.exe"
fi
test -f "$FIXTURE" || { echo "Missing fixture: $FIXTURE" >&2; exit 1; }

if test -z "$OUTPUT"; then
  stamp=$(date -u +%Y%m%dT%H%M%SZ)
  OUTPUT="$VKMT/build/perf-p0/sessions/$ARCH-$stamp"
fi
mkdir -p "$OUTPUT/traces"

mkdir -p "$(dirname "$EXEC_RUNNER")"
/usr/bin/clang -O2 -Wall -Wextra -o "$EXEC_RUNNER" "$VKMT/tools/vkmt-perf-exec.c"

runs_tsv="$OUTPUT/runs.tsv"
printf 'session\tstate\trun\trun_id\trc\telapsed_ms\tuser_s\tsystem_s\tmax_rss\tminor_faults\tmajor_faults\tblock_in\tblock_out\tvoluntary_cs\tinvoluntary_cs\n' >"$runs_tsv"

stop_server()
{
  WINEPREFIX="$PREFIX" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$PREFIX" "$WINESERVER" -w 2>/dev/null || true
}

prewarm_files()
{
  for file in "$WINE" "$BUILD/dlls/ntdll/ntdll.so" "$FIXTURE" \
      "$PREFIX/drive_c/windows/system32/xtajit64.dll" \
      "$PREFIX/drive_c/windows/system32/xtajit.dll"; do
    test -f "$file" || continue
    /bin/dd if="$file" of=/dev/null bs=1048576 2>/dev/null
  done
}

run_one()
{
  local session=$1
  local state=$2
  local number=$3
  local run_id="p0-$ARCH-s$session-$state-r$number"
  local marker="$OUTPUT/$run_id.marker"
  local rc trace_count
  local args=("$FIXTURE")
  test "$ARCH" != i386 || args+=("Z:$marker")

  env WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
    WINE_NO_EXPLORER=1 WINEDEBUG=-all MVK_CONFIG_LOG_LEVEL=0 \
    FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
    FEX_MULTIBLOCK=1 FEX_MAXINST=5000 FEX_ENABLECODECACHINGWIP="$CODE_CACHE" \
    VKMT_PERF_RUN_ID="$run_id" VKMT_PERF_TRACE_HOST_DIR="$OUTPUT/traces" \
    "$EXEC_RUNNER" "$runs_tsv" "$OUTPUT/traces/launcher.tsv" "$session" "$state" "$number" "$run_id" \
    "$WINE" "${args[@]}" >"$OUTPUT/$run_id.log" 2>&1
  rc=$?
  test "$rc" = 0 || { echo "$run_id failed with rc=$rc" >&2; return "$rc"; }
  if test -n "$EXPECT_OUTPUT"; then
    grep -Fq "$EXPECT_OUTPUT" "$OUTPUT/$run_id.log"
  elif test "$ARCH" = i386; then
    grep -q 'VKMT i386 WoW64 execution contract passed' "$marker"
  else
    grep -q 'VKMT entry_x64: hello from x86-64 guest' "$OUTPUT/$run_id.log"
  fi
  trace_count=$(find "$OUTPUT/traces" -type f -name "vkmt-perf-$run_id-*.tsv" -print | wc -l | tr -d ' ')
  test "$trace_count" -ge 1 || { echo "$run_id produced no correlated FEX trace" >&2; return 1; }
}

cleanup()
{
  status=$?
  stop_server
  printf 'status=%s\n' "$status" >"$OUTPUT/status.txt"
  exit "$status"
}
trap cleanup EXIT

for session in $(seq 1 "$SESSIONS"); do
  old_ifs=$IFS
  IFS=,
  for state in $STATES; do
    IFS=$old_ifs
    stop_server
    case "$state" in
      warm_files_cold_server) prewarm_files ;;
      persistent_server)
        "$VKMT/scripts/vkmt-warm-session.sh" start --prefix "$PREFIX" --reason perf-persistent-server >/dev/null
        run_one "$session" "${state}_primer" 0
        ;;
      persistent_session_warm_guest)
        prewarm_files
        "$VKMT/scripts/vkmt-warm-session.sh" start --prefix "$PREFIX" --reason perf-warm-guest >/dev/null
        run_one "$session" "${state}_primer" 0
        ;;
    esac
    for number in $(seq 1 "$RUNS"); do
      case "$state" in
        cold_process_cold_server|warm_files_cold_server) stop_server ;;
      esac
      run_one "$session" "$state" "$number"
    done
    IFS=,
  done
  IFS=$old_ifs
done

"$VKMT/scripts/analyze-perf-p0.sh" "$runs_tsv" "$OUTPUT/summary.tsv"
"$VKMT/tools/analyze-vkmt-perf.py" "$OUTPUT/traces" "$OUTPUT/phases.tsv"

expected=$((RUNS * SESSIONS))
repeatability="$OUTPUT/repeatability.tsv"
printf 'state\tmedian_min_ms\tmedian_max_ms\tmedian_spread_pct\tp95_min_ms\tp95_max_ms\tp95_spread_pct\tgate\n' >"$repeatability"
old_ifs=$IFS
IFS=,
for state in $STATES; do
  IFS=$old_ifs
  actual=$(awk -F '\t' -v state="$state" '$2 == state && $5 == 0 { count++ } END { print count + 0 }' "$runs_tsv")
  test "$actual" = "$expected" || { echo "$state rc=0 count $actual, expected $expected" >&2; exit 1; }
  read -r median_min median_max p95_min p95_max <<EOF
$(awk -F '\t' -v state="$state" '
  NR > 1 && $2 == state {
    if (!count++ || $4 < median_min) median_min = $4;
    if (count == 1 || $4 > median_max) median_max = $4;
    if (count == 1 || $6 < p95_min) p95_min = $6;
    if (count == 1 || $6 > p95_max) p95_max = $6;
  }
  END { print median_min, median_max, p95_min, p95_max }
' "$OUTPUT/summary.tsv")
EOF
  median_spread=$(awk -v low="$median_min" -v high="$median_max" 'BEGIN { printf "%.2f", low ? (high - low) * 100 / low : 0 }')
  p95_spread=$(awk -v low="$p95_min" -v high="$p95_max" 'BEGIN { printf "%.2f", low ? (high - low) * 100 / low : 0 }')
  gate=PASS
  awk -v median="$median_spread" -v p95="$p95_spread" 'BEGIN { exit !(median <= 5.0 && p95 <= 5.0) }' || gate=FAIL
  if test "$GATE_STATES" != all; then
    case ",$GATE_STATES," in *,$state,*) ;; *) gate=OBSERVE ;; esac
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$state" "$median_min" "$median_max" \
    "$median_spread" "$p95_min" "$p95_max" "$p95_spread" "$gate" >>"$repeatability"
  IFS=,
done
IFS=$old_ifs

cat "$repeatability"
if grep -q $'\tFAIL$' "$repeatability"; then
  echo "P0 repeatability exceeded 5%; inspect repeatability.tsv before accepting the baseline" >&2
  exit 1
fi

echo "VKMT_PERF_P0_BENCHMARK_OK output=$OUTPUT"
