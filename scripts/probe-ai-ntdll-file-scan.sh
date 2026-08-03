#!/bin/bash
# Benchmark and fuzz the pure marker-scan helper used by the opt-in Steam
# handoff notification. This is a host-native helper test; it never creates a
# Wine prefix, runs Wineboot, or stages a runtime.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd -P)"
OUT="${VKMT_AI_FILE_SCAN_OUT:-$VKMT/build/ai-ntdll-file-scan}"
CC="${VKMT_AI_FILE_SCAN_CC:-clang}"

command -v "$CC" >/dev/null 2>&1 || {
    echo "missing compiler: $CC" >&2
    exit 2
}
rm -rf "$OUT"
mkdir -p "$OUT"
"$CC" -std=c11 -O3 -Wall -Wextra \
    "$VKMT/test/perf/ntdll_file_buffer_contains.c" -o "$OUT/ntdll_file_buffer_contains"
"$OUT/ntdll_file_buffer_contains" | tee "$OUT/results.txt"
grep -q '^VKMT_NTDLL_FILE_SCAN_EQUIVALENCE_OK ' "$OUT/results.txt"
test "$(grep -c '^VKMT_NTDLL_FILE_SCAN_BENCH ' "$OUT/results.txt")" -eq 9
echo "VKMT_NTDLL_FILE_SCAN_OK output=$OUT"
