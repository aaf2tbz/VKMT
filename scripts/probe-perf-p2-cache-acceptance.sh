#!/bin/bash
# Quantify Windows FEX cache coverage/JIT reduction and prove corrupt-cache fallback.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
RUNS="$VKMT/build/probe-runs"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
X64_PROVIDER="${VKMT_XTAJIT64_SOURCE:-$VKMT/build/fex-arm64ec-steam-probe/Bin/libarm64ecfex.dll}"
I386_PROVIDER="${VKMT_XTAJIT_SOURCE:-$VKMT/build/fex-wow64-java/Bin/libwow64fex.dll}"
X64_SHA="${VKMT_XTAJIT64_SHA256:-$(shasum -a 256 "$X64_PROVIDER" | awk '{print $1}')}"
I386_SHA="${VKMT_XTAJIT_SHA256:-$(shasum -a 256 "$I386_PROVIDER" | awk '{print $1}')}"
WARM_RUNS="${VKMT_P2_WARM_RUNS:-3}"
EVIDENCE="${VKMT_P2_EVIDENCE_DIR:-}"

case "$WARM_RUNS" in ''|*[!0-9]*|0) echo "VKMT_P2_WARM_RUNS must be positive" >&2; exit 2 ;; esac
test -x "$WINE" && test -x "$WINESERVER" && test -f "$WINEBOOT"
test -f "$X64_PROVIDER" && test -f "$I386_PROVIDER"
mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/perf-p2-cache.XXXXXX")"
prefix="$run_root/prefix"
trace_dir="$run_root/traces"
mkdir -p "$prefix/drive_c/windows/system32" "$prefix/drive_c/windows/syswow64" "$trace_dir"

stop_server()
{
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
}

cleanup()
{
  status=$?
  stop_server
  printf 'status=%s\n' "$status" >"$run_root/status.txt"
  if test -n "$EVIDENCE"; then
    case "$EVIDENCE" in
      "$VKMT"/*)
        mkdir -p "$EVIDENCE"
        find "$run_root" -maxdepth 1 -type f -exec cp -p {} "$EVIDENCE/" \;
        test ! -d "$trace_dir" || cp -R "$trace_dir" "$EVIDENCE/"
        ;;
      *) echo "Refusing non-VKMT evidence directory: $EVIDENCE" >&2 ;;
    esac
  fi
  case "$run_root" in "$RUNS"/*) find "$run_root" -depth -delete 2>/dev/null || true ;; esac
  exit "$status"
}
trap cleanup EXIT

run_wine()
{
  run_id=$1
  output=$2
  shift 2
  gtimeout --signal=TERM --kill-after=10s "${VKMT_P2_TIMEOUT:-120}s" env \
    WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
    WINE_NO_EXPLORER=1 WINEDEBUG=-all MVK_CONFIG_LOG_LEVEL=0 \
    FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
    FEX_MULTIBLOCK=1 FEX_MAXINST=5000 FEX_ENABLECODECACHINGWIP=1 \
    VKMT_PERF_RUN_ID="$run_id" VKMT_PERF_TRACE_HOST_DIR="$trace_dir" \
    "$WINE" "$@" >"$output" 2>&1
  stop_server
}

summary_value()
{
  run_id=$1
  key=$2
  awk -F '\t' -v run_id="$run_id" -v key="$key" '
    $1 == "VKMT_PERF_V1" && $5 == run_id && $8 == "jit_compile_summary" {
      count = split($9, fields, " ")
      for (i = 1; i <= count; ++i) {
        split(fields[i], pair, "=")
        if (pair[1] == key) value += pair[2]
      }
    }
    END { if (value == "") exit 1; print value + 0 }
  ' "$trace_dir"/*.tsv
}

cache_detail()
{
  run_id=$1
  awk -F '\t' -v run_id="$run_id" \
    '$1 == "VKMT_PERF_V1" && $5 == run_id && $8 == "cache_enabled" { print $9; exit }' \
    "$trace_dir"/*.tsv
}

provider_env=(
  VKMT_XTAJIT64_SOURCE="$X64_PROVIDER" VKMT_XTAJIT64_SHA256="$X64_SHA"
  VKMT_XTAJIT_SOURCE="$I386_PROVIDER" VKMT_XTAJIT_SHA256="$I386_SHA"
)

for dll in wow64 wow64win; do
  install -m 0644 "$BUILD/dlls/$dll/aarch64-windows/$dll.dll" \
    "$prefix/drive_c/windows/system32/$dll.dll"
done
while IFS= read -r dll; do
  install -m 0644 "$dll" "$prefix/drive_c/windows/syswow64/$(basename "$dll")"
done < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)

env "${provider_env[@]}" "$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
run_wine p2-wineboot "$run_root/wineboot.log" "$WINEBOOT" --init
env "${provider_env[@]}" "$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
env "${provider_env[@]}" "$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"

"$TOOL/x86_64-w64-mingw32-clang" -O2 -o "$run_root/x86_64.exe" "$VKMT/test/x64emu/entry_x64.c"
"$TOOL/i686-w64-mingw32-clang" -O2 -o "$run_root/i386.exe" "$VKMT/test/i386_smoke.c"

printf 'arch\tcold_blocks\twarm_max_blocks\tcoverage_pct\tcold_jit_ns\twarm_max_jit_ns\tjit_reduction_pct\tcached_blocks\n' \
  >"$run_root/metrics.tsv"

completed_arches=0
for arch in x86_64 i386; do
  marker="$run_root/$arch.marker"
  args=("$run_root/$arch.exe")
  test "$arch" != i386 || args+=("Z:$marker")

  run_wine "p2-$arch-cold" "$run_root/$arch-cold.log" "${args[@]}"
  test "$arch" = i386 || grep -q 'VKMT entry_x64: hello from x86-64 guest' "$run_root/$arch-cold.log"
  test "$arch" != i386 || grep -q 'VKMT i386 WoW64 execution contract passed' "$marker"
  cold_blocks="$(summary_value "p2-$arch-cold" eligible_blocks)"
  cold_jit_ns="$(summary_value "p2-$arch-cold" eligible_nanoseconds)"
  test "$cold_blocks" -gt 0 && test "$cold_jit_ns" -gt 0

  warm_max_blocks=0
  warm_max_jit_ns=0
  cached_blocks=0
  for number in $(seq 1 "$WARM_RUNS"); do
    run_id="p2-$arch-warm-$number"
    run_wine "$run_id" "$run_root/$arch-warm-$number.log" "${args[@]}"
    blocks="$(summary_value "$run_id" eligible_blocks)"
    jit_ns="$(summary_value "$run_id" eligible_nanoseconds)"
    detail="$(cache_detail "$run_id")"
    test -n "$detail"
    current_cached="$(printf '%s\n' "$detail" | sed -n 's/.* blocks=\([0-9][0-9]*\).*/\1/p')"
    test -n "$current_cached" && test "$current_cached" -gt 0
    test "$blocks" -le "$warm_max_blocks" || warm_max_blocks=$blocks
    test "$jit_ns" -le "$warm_max_jit_ns" || warm_max_jit_ns=$jit_ns
    test "$current_cached" -le "$cached_blocks" || cached_blocks=$current_cached
  done

  coverage="$(awk -v cold="$cold_blocks" -v warm="$warm_max_blocks" \
    'BEGIN { printf "%.2f", 100 * (cold - warm) / cold }')"
  reduction="$(awk -v cold="$cold_jit_ns" -v warm="$warm_max_jit_ns" \
    'BEGIN { printf "%.2f", 100 * (cold - warm) / cold }')"
  awk -v value="$coverage" 'BEGIN { exit !(value >= 80.0) }'
  awk -v value="$reduction" 'BEGIN { exit !(value >= 70.0) }'
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$arch" "$cold_blocks" \
    "$warm_max_blocks" "$coverage" "$cold_jit_ns" "$warm_max_jit_ns" "$reduction" "$cached_blocks" \
    >>"$run_root/metrics.tsv"

  cache_id="$(cache_detail "p2-$arch-warm-1" | sed -n 's/^id=\([^ ]*\) blocks=.*/\1/p')"
  cache_file="$(find "$prefix" -type f -path "*/fex-emu/cache/$cache_id/*" ! -name '*.new' -print -quit)"
  test -f "$cache_file"
  /bin/dd if=/dev/zero of="$cache_file" bs=64 count=1 conv=notrunc 2>/dev/null
  run_wine "p2-$arch-corrupt" "$run_root/$arch-corrupt.log" "${args[@]}"
  corrupt_blocks="$(summary_value "p2-$arch-corrupt" eligible_blocks)"
  test "$corrupt_blocks" -gt 0
  if cache_detail "p2-$arch-corrupt" | grep -q .; then
    echo "$arch corrupt cache was unexpectedly enabled" >&2
    exit 1
  fi
  arch_marker="$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')"
  echo "P2_${arch_marker}_CORRUPTION_FALLBACK_OK"
  completed_arches=$((completed_arches + 1))
done

test "$completed_arches" -eq 2
cat "$run_root/metrics.tsv"
echo P2_CACHE_ACCEPTANCE_OK
