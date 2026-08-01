#!/bin/bash
# Summarize a P0 runs.tsv using nearest-rank percentiles.
set -euo pipefail

input=${1:?usage: analyze-perf-p0.sh RUNS_TSV [SUMMARY_TSV]}
output=${2:-${input%/*}/summary.tsv}
test -f "$input" || { echo "Missing input: $input" >&2; exit 1; }

printf 'session\tstate\truns\tmedian_ms\tp90_ms\tp95_ms\tmin_ms\tmax_ms\trc0\n' >"$output"

percentile()
{
  p=$1
  awk -v p="$p" '{ values[NR] = $1 } END { if (!NR) exit 1; idx = int(NR * p); if (idx < NR * p) idx++; if (idx < 1) idx = 1; print values[idx] }'
}

tail -n +2 "$input" | awk -F '\t' '{ print $1 "\t" $2 }' | LC_ALL=C sort -u |
while IFS=$'\t' read -r session state; do
  values=$(mktemp "${TMPDIR:-/tmp}/vkmt-p0-values.XXXXXX")
  awk -F '\t' -v session="$session" -v state="$state" \
    '$1 == session && $2 == state { print $6 }' "$input" | LC_ALL=C sort -n >"$values"
  runs=$(wc -l <"$values" | tr -d ' ')
  median=$(percentile 0.50 <"$values")
  p90=$(percentile 0.90 <"$values")
  p95=$(percentile 0.95 <"$values")
  minimum=$(head -n 1 "$values")
  maximum=$(tail -n 1 "$values")
  rc0=$(awk -F '\t' -v session="$session" -v state="$state" \
    '$1 == session && $2 == state && $5 == 0 { count++ } END { print count + 0 }' "$input")
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$session" "$state" "$runs" "$median" "$p90" "$p95" "$minimum" "$maximum" "$rc0" >>"$output"
  find "$values" -delete
done

cat "$output"
