#!/bin/bash
# Compare i386 executable-memory maintenance and prove the P7 no-TSO gates.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
RUNS="$VKMT/build/probe-runs"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
BASELINE="${VKMT_P7_BASELINE_PROVIDER:-$VKMT/build/fex-p7-baseline/provider/xtajit.dll}"
CANDIDATE="${VKMT_P7_CANDIDATE_PROVIDER:-$VKMT/build/fex-p7-candidate/provider/xtajit.dll}"
X64_PROVIDER="${VKMT_XTAJIT64_SOURCE:-$VKMT/wine/wine-11.12/runtime-providers/xtajit64-arm64ec-known-good.dll}"
EVIDENCE="${VKMT_P7_EVIDENCE_DIR:-$VKMT/build/evidence/perf-p7}"

for file in "$WINE" "$WINESERVER" "$WINEBOOT" "$BASELINE" "$CANDIDATE" "$X64_PROVIDER"; do
  test -e "$file" || { echo "Missing P7 input: $file" >&2; exit 1; }
done
if translated="$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null)"; then
  test "$translated" = 0 || { echo "P7 runner is under Rosetta" >&2; exit 1; }
fi

mkdir -p "$RUNS" "$EVIDENCE"
run_root="$(mktemp -d "$RUNS/perf-p7.XXXXXX")"
trace_dir="$run_root/traces"
mkdir -p "$trace_dir"
status=1
active_prefix=

cleanup()
{
  test -z "$active_prefix" || WINEPREFIX="$active_prefix" "$WINESERVER" -k 2>/dev/null || true
  test -z "$active_prefix" || WINEPREFIX="$active_prefix" "$WINESERVER" -w 2>/dev/null || true
  printf 'status=%s\n' "$status" >"$run_root/status.txt"
  if test -d "$EVIDENCE"; then
    find "$run_root" -maxdepth 1 -type f -exec cp -p {} "$EVIDENCE/" \;
    test ! -d "$EVIDENCE/traces" || find "$EVIDENCE/traces" -depth -delete
    cp -R "$trace_dir" "$EVIDENCE/traces"
  fi
  case "$run_root" in "$RUNS"/*) find "$run_root" -depth -delete 2>/dev/null || true ;; esac
}
trap cleanup EXIT

"$TOOL/i686-w64-mingw32-clang" -O2 -Wall -Wextra \
  -o "$run_root/smc-i386.exe" "$VKMT/test/i386/smc.c"

summary_value()
{
  run_id=$1
  key=$2
  awk -F '\t' -v run_id="$run_id" -v key="$key" '
    $1 == "VKMT_PERF_V1" && $5 == run_id && $8 == "maintenance_summary" {
      count = split($9, fields, " ")
      for (i = 1; i <= count; ++i) {
        split(fields[i], pair, "=")
        if (pair[1] == key) value += pair[2]
      }
    }
    END { if (value == "") exit 1; print value + 0 }
  ' "$trace_dir"/*.tsv
}

run_case()
{
  label=$1
  provider=$2
  provider_sha="$(shasum -a 256 "$provider" | awk '{print $1}')"
  x64_sha="$(shasum -a 256 "$X64_PROVIDER" | awk '{print $1}')"
  active_prefix="$run_root/prefix-$label"
  mkdir -p "$active_prefix/drive_c/windows/system32" "$active_prefix/drive_c/windows/syswow64"
  install -m 0644 "$BUILD/dlls/wow64/aarch64-windows/wow64.dll" "$active_prefix/drive_c/windows/system32/wow64.dll"
  install -m 0644 "$BUILD/dlls/wow64win/aarch64-windows/wow64win.dll" "$active_prefix/drive_c/windows/system32/wow64win.dll"
  while IFS= read -r dll; do
    install -m 0644 "$dll" "$active_prefix/drive_c/windows/syswow64/$(basename "$dll")"
  done < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)
  env VKMT_XTAJIT64_SOURCE="$X64_PROVIDER" VKMT_XTAJIT64_SHA256="$x64_sha" \
    VKMT_XTAJIT_SOURCE="$provider" VKMT_XTAJIT_SHA256="$provider_sha" \
    "$VKMT/scripts/stage-runtime-providers.sh" --prefix "$active_prefix" >"$run_root/$label-stage.log"
  env WINEPREFIX="$active_prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 WINE_NO_EXPLORER=1 WINEDEBUG=-all \
    FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
    "$WINE" "$WINEBOOT" --init >"$run_root/$label-wineboot.log" 2>&1
  WINEPREFIX="$active_prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$active_prefix" "$WINESERVER" -w 2>/dev/null || true
  env VKMT_XTAJIT64_SOURCE="$X64_PROVIDER" VKMT_XTAJIT64_SHA256="$x64_sha" \
    VKMT_XTAJIT_SOURCE="$provider" VKMT_XTAJIT_SHA256="$provider_sha" \
    "$VKMT/scripts/stage-runtime-providers.sh" --prefix "$active_prefix" >>"$run_root/$label-stage.log"
  run_id="p7-$label-smc"
  gtimeout --signal=TERM --kill-after=5s "${VKMT_P7_TIMEOUT:-60}s" env \
    WINEPREFIX="$active_prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 WINE_NO_EXPLORER=1 WINEDEBUG=-all \
    FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
    VKMT_PERF_RUN_ID="$run_id" VKMT_PERF_TRACE_HOST_DIR="$trace_dir" \
    "$WINE" "$run_root/smc-i386.exe" >"$run_root/$label-smc.log" 2>&1
  WINEPREFIX="$active_prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$active_prefix" "$WINESERVER" -w 2>/dev/null || true
  active_prefix=
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$label" \
    "$(summary_value "$run_id" flush_requests)" "$(summary_value "$run_id" flush_passes)" \
    "$(summary_value "$run_id" invalidation_passes)" "$(summary_value "$run_id" protection_calls)" \
    "$(summary_value "$run_id" rwx_write_faults)" >>"$run_root/metrics.tsv"
}

printf 'provider\tflush_requests\tflush_passes\tinvalidation_passes\tprotection_calls\trwx_write_faults\n' >"$run_root/metrics.tsv"
run_case baseline "$BASELINE"
run_case candidate "$CANDIDATE"

baseline_passes="$(awk -F '\t' '$1 == "baseline" {print $3}' "$run_root/metrics.tsv")"
candidate_passes="$(awk -F '\t' '$1 == "candidate" {print $3}' "$run_root/metrics.tsv")"
test "$baseline_passes" -gt 0 && test "$candidate_passes" -gt 0
reduction="$(awk -v old="$baseline_passes" -v new="$candidate_passes" 'BEGIN { printf "%.2f", 100 * (old - new) / old }')"
printf 'flush_pass_reduction_pct\t%s\n' "$reduction" >>"$run_root/metrics.tsv"
awk -v value="$reduction" 'BEGIN { exit !(value >= 50.0) }'

cp "$run_root/metrics.tsv" "$EVIDENCE/metrics.tsv"
status=0
echo "P7_EXECUTABLE_MEMORY_OK reduction_pct=$reduction"
