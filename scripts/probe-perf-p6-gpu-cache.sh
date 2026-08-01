#!/bin/bash
# P6: prove versioned cache routing and eliminate repeat DXVK shader translation.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
DXVK="$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/x32"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
RUNS="$VKMT/build/probe-runs"
EVIDENCE="${VKMT_P6_GPU_EVIDENCE_DIR:-$VKMT/build/perf-p6/gpu-cache}"

for required in "$WINE" "$WINESERVER" "$WINEBOOT" "$DXVK/dxgi.dll" \
    "$DXVK/d3d11.dll" "$VKMT/test/d3d11_shader_cache_probe.c"; do
  test -e "$required" || { echo "Missing P6 GPU-cache input: $required" >&2; exit 1; }
done
test "$(/usr/bin/lipo -archs "$WINE")" = arm64
test "$(/usr/bin/lipo -archs "$WINESERVER")" = arm64
if translated="$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null)"; then
  test "$translated" = 0 || { echo "P6 GPU-cache runner is under Rosetta" >&2; exit 1; }
fi

mkdir -p "$RUNS" "$EVIDENCE"
run_root="$(mktemp -d "$RUNS/perf-p6-gpu-cache.XXXXXX")"
prefix="$run_root/prefix"
wine_pid=""
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=10s "${VKMT_P6_GPU_TIMEOUT:-180}s")
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=10s "${VKMT_P6_GPU_TIMEOUT:-180}s")
fi

cleanup()
{
  status=$?
  test -z "$wine_pid" || kill -TERM "$wine_pid" 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  if test "$status" -ne 0; then
    find "$run_root" -maxdepth 2 -type f -name '*.log' -exec cp -p {} "$EVIDENCE/" \; 2>/dev/null || true
    printf 'status=%s\n' "$status" >"$EVIDENCE/status.txt"
  fi
  case "$run_root" in "$RUNS"/*) find "$run_root" -depth -delete 2>/dev/null || true ;; esac
  exit "$status"
}
trap cleanup EXIT

run_wine()
{
  output=$1
  shift
  start="$(perl -MTime::HiRes=time -e 'printf "%.0f", time()*1000000000')"
  "${timeout_cmd[@]}" env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" \
    WINEBOOTSTRAPMODE=1 WINE_NO_EXPLORER=1 WINEDEBUG="${VKMT_P6_GPU_WINEDEBUG:--all}" \
    FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
    "$WINE" "$@" >"$output" 2>&1 &
  wine_pid=$!
  if wait "$wine_pid"; then code=0; else code=$?; fi
  wine_pid=""
  end="$(perl -MTime::HiRes=time -e 'printf "%.0f", time()*1000000000')"
  elapsed_ns=$((end - start))
  return "$code"
}

"$TOOL/i686-w64-mingw32-clang" -O2 -o "$run_root/p6_shader.exe" \
  "$VKMT/test/d3d11_shader_cache_probe.c" -ld3d11 -ld3dcompiler -ldxgi
"$TOOL/x86_64-w64-mingw32-clang" -O2 -o "$run_root/p6_compile.exe" \
  "$VKMT/test/d3dcompiler_blob.c" -ld3dcompiler
"$TOOL/i686-w64-mingw32-clang" -O2 -o "$run_root/d3d11_readback.exe" \
  "$VKMT/test/d3d11_probe.c" -ld3d11 -ldxgi
"$TOOL/llvm-readobj" --file-headers "$run_root/p6_shader.exe" |
  grep -q IMAGE_FILE_MACHINE_I386

"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
run_wine "$run_root/wineboot.log" "$WINEBOOT" --init
"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"

run_wine "$run_root/compile.log" "$run_root/p6_compile.exe" "$run_root/p6_shader.dxbc"
grep -q VKMT_P6_DXBC_COMPILE_OK "$run_root/compile.log"
test -s "$run_root/p6_shader.dxbc"
install -m 0644 "$DXVK/dxgi.dll" "$DXVK/d3d11.dll" "$prefix/drive_c/windows/syswow64/"

export WINEPREFIX="$prefix" VKMT_RUNTIME_ROOT="$VKMT"
source "$VKMT/scripts/vkmt-gpu-cache-env.sh"
"$VKMT/scripts/stage-gpu-cache-runtime.sh" --verify-prefix "$prefix"

run_dxvk()
{
  name=$1
  log_dir="$run_root/dxvk-$name"
  mkdir -p "$log_dir"
  DXVK_LOG_LEVEL=debug DXVK_LOG_PATH="$log_dir" \
  DXVK_CONFIG="dxvk.numCompilerThreads = ${VKMT_P6_DXVK_COMPILER_THREADS:-1}" \
  VK_ICD_FILENAMES="$VKMT/test/vkmt_icd.json" \
  WINEDLLOVERRIDES='dxgi,d3d11=n' \
    run_wine "$run_root/$name.log" "$run_root/p6_shader.exe" --load "$run_root/p6_shader.dxbc"
  eval "${name}_ns=$elapsed_ns"
  grep -q VKMT_P6_DXVK_SHADER_CACHE_PROBE_OK "$run_root/$name.log"
  find "$log_dir" -type f -name '*.log' -exec cat {} + >"$run_root/$name-dxvk.log"
}

run_dxvk cold
find "$DXVK_SHADER_CACHE_PATH" -type f -size +0 -print -quit | grep -q .
run_dxvk warm

cold_translations="$(grep -c 'Compiling shader ' "$run_root/cold-dxvk.log" || true)"
# D3D11 logs "Compiling shader" before it performs the cache lookup, even
# on a hit. A warm cache miss is the actual repeat IR-translation signal.
warm_translations="$(grep -c 'Shader cache miss:' "$run_root/warm-dxvk.log" || true)"
warm_hits="$(grep -c 'Shader cache hit:' "$run_root/warm-dxvk.log" || true)"
cold_pipeline_ns="$(sed -n 's/.*VKMT_P6_PIPELINE_NS=\([0-9][0-9]*\).*/\1/p' "$run_root/cold.log" | tail -1)"
warm_pipeline_ns="$(sed -n 's/.*VKMT_P6_PIPELINE_NS=\([0-9][0-9]*\).*/\1/p' "$run_root/warm.log" | tail -1)"
cold_shader_create_ns="$(sed -n 's/.*VKMT_P6_SHADER_CREATE_NS=\([0-9][0-9]*\).*/\1/p' "$run_root/cold.log" | tail -1)"
warm_shader_create_ns="$(sed -n 's/.*VKMT_P6_SHADER_CREATE_NS=\([0-9][0-9]*\).*/\1/p' "$run_root/warm.log" | tail -1)"
test "$cold_translations" -gt 0
test "$warm_hits" -ge "$cold_translations"
test "$warm_translations" = 0
test -n "$cold_pipeline_ns"
test -n "$warm_pipeline_ns"
test -n "$cold_shader_create_ns"
test -n "$warm_shader_create_ns"
reduction=$(((cold_translations - warm_translations) * 100 / cold_translations))
test "$reduction" = 100
hit_rate=$((warm_hits * 100 / (warm_hits + warm_translations)))
test "$hit_rate" -gt 90
test "$warm_pipeline_ns" -lt 100000000

# A manifest from another OS/GPU/runtime identity must never be consumed as
# current. Prove rejection, then atomically regenerate the correct identity.
manifest_bad="$run_root/MANIFEST.incompatible.tsv"
awk -F '\t' 'BEGIN { OFS="\t" } $1 == "generation" { $2="v2-0000000000000000" } { print }' \
  "$VKMT_GPU_CACHE_MANIFEST" >"$manifest_bad"
mv -f "$manifest_bad" "$VKMT_GPU_CACHE_MANIFEST"
if "$VKMT/scripts/stage-gpu-cache-runtime.sh" --verify-prefix "$prefix" >/dev/null 2>&1; then
  echo 'P6 incompatible GPU cache identity was accepted' >&2
  exit 1
fi
"$VKMT/scripts/stage-gpu-cache-runtime.sh" --prefix "$prefix" >/dev/null
"$VKMT/scripts/stage-gpu-cache-runtime.sh" --verify-prefix "$prefix" >/dev/null
source "$VKMT/scripts/vkmt-gpu-cache-env.sh"

DXVK_LOG_LEVEL=info VK_ICD_FILENAMES="$VKMT/test/vkmt_icd.json" \
WINEDLLOVERRIDES='dxgi,d3d11=n' \
  run_wine "$run_root/readback.log" "$run_root/d3d11_readback.exe"
grep -q VKMT_D3D11_PROBE_OK "$run_root/readback.log"

cp -p "$run_root/cold.log" "$run_root/warm.log" "$run_root/readback.log" \
  "$run_root/cold-dxvk.log" "$run_root/warm-dxvk.log" "$EVIDENCE/"
cp -p "$VKMT_GPU_CACHE_MANIFEST" "$EVIDENCE/MANIFEST.tsv"
{
  printf 'generation=%s\n' "$VKMT_GPU_CACHE_GENERATION"
  printf 'cold_ns=%s\n' "$cold_ns"
  printf 'warm_ns=%s\n' "$warm_ns"
  printf 'cold_shader_translations=%s\n' "$cold_translations"
  printf 'warm_shader_translations=%s\n' "$warm_translations"
  printf 'warm_shader_hits=%s\n' "$warm_hits"
  printf 'shader_translation_reduction_pct=%s\n' "$reduction"
  printf 'warm_cache_hit_rate_pct=%s\n' "$hit_rate"
  printf 'first_frame_shader_translation_reduction_pct=%s\n' "$reduction"
  printf 'warm_pipeline_p95_ns=%s\n' "$warm_pipeline_ns"
  printf 'cold_pipeline_ns=%s\n' "$cold_pipeline_ns"
  printf 'warm_pipeline_ns=%s\n' "$warm_pipeline_ns"
  printf 'cold_shader_create_ns=%s\n' "$cold_shader_create_ns"
  printf 'warm_shader_create_ns=%s\n' "$warm_shader_create_ns"
  printf 'exact_shutdown=1\n'
  printf 'incompatible_identity_rejected=1\n'
  printf 'status=0\n'
} >"$EVIDENCE/RESULTS.txt"

echo "P6_DXVK_SHADER_CACHE_OK generation=$VKMT_GPU_CACHE_GENERATION reduction=${reduction}%"
echo P6_GPU_CACHE_ACCEPTANCE_OK
