#!/bin/bash
# Prove bounded hot-set prefetch, cold stall reduction, GB/s, and warm safety.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="${VKMT_P8_PREFIX:-$VKMT/prefixes/steam-no-tso-phase6}"
MANIFEST="${VKMT_P8_MANIFEST:-$VKMT/runtime/hotsets/all-arch-default.tsv}"
RUNS="${VKMT_P8_RUNS:-5}"
LEAD_MS="${VKMT_P8_LEAD_MS:-100}"
PREFETCH="$VKMT/build/tools/vkmt-hotset-prefetch"
RUNS_ROOT="$VKMT/build/probe-runs"
EVIDENCE="${VKMT_P8_EVIDENCE_DIR:-$VKMT/build/evidence/perf-p8}"

case "$RUNS:$LEAD_MS" in *[!0-9:]*|0:*) echo "Invalid P8 run configuration" >&2; exit 2 ;; esac
test -d "$PREFIX" && test -f "$MANIFEST"
test "$(/usr/bin/uname -m)" = arm64
if translated="$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null)"; then
  test "$translated" = 0 || { echo "P8 runner is under Rosetta" >&2; exit 1; }
fi

mkdir -p "$RUNS_ROOT" "$EVIDENCE" "$(dirname "$PREFETCH")"
/usr/bin/clang -O2 -Wall -Wextra -Werror "$VKMT/tools/vkmt-hotset-prefetch.c" -o "$PREFETCH"
run_root="$(mktemp -d "$RUNS_ROOT/perf-p8.XXXXXX")"
status=1
cleanup()
{
  printf 'status=%s\n' "$status" >"$run_root/status.txt"
  find "$EVIDENCE" -depth -delete 2>/dev/null || true
  mkdir -p "$EVIDENCE"
  find "$run_root" -maxdepth 1 -type f ! -name '*.pack' -exec cp -p {} "$EVIDENCE/" \;
  case "$run_root" in "$RUNS_ROOT"/*) find "$run_root" -depth -delete 2>/dev/null || true ;; esac
}
trap cleanup EXIT

extract()
{
  key=$1
  file=$2
  sed -n "s/.* $key=\([^ ]*\).*/\1/p" "$file"
}

printf 'run\tphysical_ns\tphysical_gbps\tprefetch_advice_ns\tprefetch_stall_ns\tprefetch_effective_gbps\tprefetch_total_gbps\tstall_reduction_pct\n' >"$run_root/runs.tsv"
for run in $(seq 1 "$RUNS"); do
  baseline="$run_root/baseline-$run.pack"
  candidate="$run_root/prefetch-$run.pack"
  "$PREFETCH" "$MANIFEST" "$VKMT" "$PREFIX" --pack "$baseline" >"$run_root/baseline-$run-pack.log"
  "$PREFETCH" --measure-pack "$baseline" physical >"$run_root/baseline-$run.log"
  find "$baseline" -delete
  "$PREFETCH" "$MANIFEST" "$VKMT" "$PREFIX" --pack "$candidate" >"$run_root/prefetch-$run-pack.log"
  "$PREFETCH" --measure-pack "$candidate" prefetch "$LEAD_MS" >"$run_root/prefetch-$run.log"
  find "$candidate" -delete

  bytes="$(extract bytes "$run_root/baseline-$run.log")"
  physical_ns="$(extract stall_ns "$run_root/baseline-$run.log")"
  physical_gbps="$(extract gbps "$run_root/baseline-$run.log")"
  advice_ns="$(extract advice_ns "$run_root/prefetch-$run.log")"
  prefetch_ns="$(extract stall_ns "$run_root/prefetch-$run.log")"
  prefetch_gbps="$(extract gbps "$run_root/prefetch-$run.log")"
  total_gbps="$(awk -v bytes="$bytes" -v advice="$advice_ns" -v lead="$LEAD_MS" -v stall="$prefetch_ns" \
    'BEGIN { printf "%.6f", bytes / (advice + lead * 1000000 + stall) }')"
  reduction="$(awk -v old="$physical_ns" -v new="$prefetch_ns" \
    'BEGIN { printf "%.2f", 100 * (old - new) / old }')"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$run" "$physical_ns" "$physical_gbps" \
    "$advice_ns" "$prefetch_ns" "$prefetch_gbps" "$total_gbps" "$reduction" >>"$run_root/runs.tsv"
done

median_column()
{
  column=$1
  awk -F '\t' -v column="$column" 'NR > 1 {print $column}' "$run_root/runs.tsv" |
    LC_ALL=C sort -n | awk '{value[NR]=$1} END {print value[int((NR + 1) / 2)]}'
}

physical_ns="$(median_column 2)"
physical_gbps="$(median_column 3)"
advice_ns="$(median_column 4)"
prefetch_ns="$(median_column 5)"
effective_gbps="$(median_column 6)"
total_gbps="$(median_column 7)"
reduction="$(median_column 8)"
awk -v value="$reduction" 'BEGIN { exit !(value >= 25.0) }'

# A cached pack must not become slower after a redundant advisory request.
warm_pack="$run_root/warm.pack"
"$PREFETCH" "$MANIFEST" "$VKMT" "$PREFIX" --pack "$warm_pack" >"$run_root/warm-pack.log"
"$PREFETCH" --measure-pack "$warm_pack" warm >"$run_root/warm-primer.log"
printf 'run\twarm_ns\tadvised_warm_ns\n' >"$run_root/warm.tsv"
for run in $(seq 1 "$RUNS"); do
  "$PREFETCH" --measure-pack "$warm_pack" warm >"$run_root/warm-$run.log"
  "$PREFETCH" --measure-pack "$warm_pack" prefetch 0 >"$run_root/warm-advised-$run.log"
  printf '%s\t%s\t%s\n' "$run" "$(extract stall_ns "$run_root/warm-$run.log")" \
    "$(extract stall_ns "$run_root/warm-advised-$run.log")" >>"$run_root/warm.tsv"
done
find "$warm_pack" -delete
warm_ns="$(awk -F '\t' 'NR>1 {print $2}' "$run_root/warm.tsv" | sort -n | awk '{v[NR]=$1} END {print v[int((NR+1)/2)]}')"
warm_advised_ns="$(awk -F '\t' 'NR>1 {print $3}' "$run_root/warm.tsv" | sort -n | awk '{v[NR]=$1} END {print v[int((NR+1)/2)]}')"
warm_regression="$(awk -v old="$warm_ns" -v new="$warm_advised_ns" 'BEGIN {printf "%.2f", 100*(new-old)/old}')"
awk -v value="$warm_regression" 'BEGIN { exit !(value <= 10.0) }'

# Identity mismatch must reject the stale row while valid rows continue.
awk -F '\t' 'BEGIN {OFS="\t"} NR == 2 {$5 += 1} {print}' "$MANIFEST" >"$run_root/incompatible.tsv"
"$PREFETCH" "$run_root/incompatible.tsv" "$VKMT" "$PREFIX" --advice >"$run_root/incompatible.log"
rejected="$(extract rejected "$run_root/incompatible.log")"
test "$rejected" -ge 1

{
  printf 'metric\tvalue\n'
  printf 'hotset_bytes\t%s\n' "$bytes"
  printf 'cold_physical_stall_ns_median\t%s\n' "$physical_ns"
  printf 'cold_physical_gbps_median\t%s\n' "$physical_gbps"
  printf 'prefetch_advice_ns_median\t%s\n' "$advice_ns"
  printf 'prefetched_blocking_stall_ns_median\t%s\n' "$prefetch_ns"
  printf 'prefetched_effective_gbps_median\t%s\n' "$effective_gbps"
  printf 'prefetched_total_delivery_gbps_median\t%s\n' "$total_gbps"
  printf 'blocking_stall_reduction_pct_median\t%s\n' "$reduction"
  printf 'warm_stall_ns_median\t%s\n' "$warm_ns"
  printf 'warm_advised_stall_ns_median\t%s\n' "$warm_advised_ns"
  printf 'warm_regression_pct\t%s\n' "$warm_regression"
  printf 'incompatible_rows_rejected\t%s\n' "$rejected"
} >"$run_root/metrics.tsv"

status=0
echo "P8_HOTSET_OK physical_gbps=$physical_gbps effective_gbps=$effective_gbps total_gbps=$total_gbps stall_reduction_pct=$reduction warm_regression_pct=$warm_regression"
