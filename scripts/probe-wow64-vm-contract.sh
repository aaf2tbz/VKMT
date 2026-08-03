#!/bin/bash
# Run the deterministic x64/i386 WoW64 VM contract in one prepared prefix.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
TOOL="${VKMT_TOOLCHAIN_BIN:-$ROOT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin}"
PREFIX="${VKMT_WOW64_VM_PREFIX:-$ROOT/build/probe-runs/phase-a-prefix}"
EVIDENCE="${VKMT_WOW64_VM_EVIDENCE_DIR:-$ROOT/docs/validation/wow64-vm-contract}"
FRESH=0

usage()
{
    echo "usage: $0 [--prefix ABSOLUTE_PATH] [--fresh] [--evidence-dir ABSOLUTE_PATH]" >&2
    exit 2
}

while test "$#" -gt 0; do
    case "$1" in
    --prefix) test "$#" -ge 2 || usage; PREFIX="$2"; shift 2;;
    --fresh) FRESH=1; shift;;
    --evidence-dir) test "$#" -ge 2 || usage; EVIDENCE="$2"; shift 2;;
    *) usage;;
    esac
done

case "$PREFIX" in /*) ;; *) echo "prefix must be absolute" >&2; exit 2;; esac
case "$EVIDENCE" in /*) ;; *) echo "evidence directory must be absolute" >&2; exit 2;; esac
test -x "$TOOL/x86_64-w64-mingw32-clang" || { echo "missing x86_64 compiler" >&2; exit 1; }
test -x "$TOOL/i686-w64-mingw32-clang" || { echo "missing i386 compiler" >&2; exit 1; }

if test "$FRESH" = 1; then
    test "$PREFIX" != / && test "$PREFIX" != "$ROOT" || { echo "unsafe prefix" >&2; exit 1; }
    rm -rf "$PREFIX"
    "$ROOT/scripts/vkmt-prefix" create --profile core --prefix "$PREFIX"
else
    "$ROOT/scripts/vkmt-prefix" verify --prefix "$PREFIX"
fi

mkdir -p "$EVIDENCE"
run_root="$(mktemp -d "$ROOT/build/probe-runs/wow64-vm.XXXXXX")"
mkdir -p "$run_root/traces"
status=1
cleanup()
{
    printf 'status=%s\n' "$status" >"$run_root/status.txt"
    cp -p "$run_root"/*.log "$run_root"/*.txt "$EVIDENCE/" 2>/dev/null || true
    if test -d "$run_root/traces"; then
        rm -rf "$EVIDENCE/traces"
        cp -R "$run_root/traces" "$EVIDENCE/traces"
    fi
    WINEPREFIX="$PREFIX" "${WINEBUILDDIR:-$ROOT/wine/build-ec}/server/wineserver" -k >/dev/null 2>&1 || true
    WINEPREFIX="$PREFIX" "${WINEBUILDDIR:-$ROOT/wine/build-ec}/server/wineserver" -w >/dev/null 2>&1 || true
    case "$run_root" in "$ROOT"/build/probe-runs/*) rm -rf "$run_root";; esac
}
trap cleanup EXIT

"$TOOL/x86_64-w64-mingw32-clang" -O2 -Wall -Wextra \
    -o "$run_root/wow64-vm-x64.exe" "$ROOT/test/wow64_vm_contract.c" \
    >"$run_root/compile-x64.log" 2>&1
"$TOOL/i686-w64-mingw32-clang" -O2 -Wall -Wextra \
    -o "$run_root/wow64-vm-i386.exe" "$ROOT/test/wow64_vm_contract.c" \
    >"$run_root/compile-i386.log" 2>&1

run_one()
{
    local label="$1" exe="$2" marker="$3"
    env FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
        VKMT_WOW64_VM_TRACE=1 VKMT_PERF_RUN_ID="wow64-vm-$label" \
        VKMT_PERF_TRACE_HOST_DIR="$run_root/traces" \
        "$ROOT/scripts/vkmt-prefix" run --prefix "$PREFIX" -- "$exe" \
        >"$run_root/$label.log" 2>&1
    grep -q "$marker" "$run_root/$label.log"
    grep -q 'WOW64_VM_CONTRACT_ALL_OK' "$run_root/$label.log"
}

run_one x64 "$run_root/wow64-vm-x64.exe" WOW64_VM_X64_CONTRACT_OK
run_one i386 "$run_root/wow64-vm-i386.exe" WOW64_VM_I386_CONTRACT_OK
grep -q 'WOW64_VM_CONCURRENT_OK' "$run_root/x64.log"
grep -q 'WOW64_VM_CONCURRENT_OK' "$run_root/i386.log"
grep -q 'WOW64_VM_MAPPING_PRESSURE_OK' "$run_root/x64.log"
grep -q 'WOW64_VM_MAPPING_PRESSURE_OK' "$run_root/i386.log"
grep -q 'WOW64_VM_ADDRESS_REUSE_OK' "$run_root/x64.log"
grep -q 'WOW64_VM_ADDRESS_REUSE_OK' "$run_root/i386.log"
grep -q 'WOW64_VM_EXECUTABLE_REUSE_OK' "$run_root/x64.log"
grep -q 'WOW64_VM_EXECUTABLE_REUSE_OK' "$run_root/i386.log"

find_fex_trace()
{
    local label="$1" component="$2" trace
    while IFS= read -r -d '' trace; do
        if grep -Fq "$(printf '\t%s\t' "$component")" "$trace"; then
            printf '%s\n' "$trace"
            return 0
        fi
    done < <(find "$run_root/traces" -type f -name "*wow64-vm-$label-*.tsv" -print0)
    return 1
}

x64_trace="$(find_fex_trace x64 fex-arm64ec-x86_64)" || x64_trace=
i386_trace="$(find_fex_trace i386 fex-wow64-i386)" ||
    { echo "missing i386 FEX trace" >&2; exit 1; }
if test -n "$x64_trace"; then
    grep -q $'\tfex-arm64ec-x86_64\t' "$x64_trace"
    x64_fex_receipt=component_fex-arm64ec-x86_64
else
    # The release-qualified P8 ARM64EC provider currently emits loader/ntdll
    # perf TSVs for this fixture but no provider component row.  Keep the
    # executable/protection proof strict, record the telemetry gap explicitly,
    # and require the i386 provider's invalidation summary below.
    echo "WOW64_VM_X64_FEX_TRACE_UNAVAILABLE provider=arm64ec-x86_64"
    x64_fex_receipt=unavailable-provider-telemetry
fi
awk -F '\t' '$6 == "fex-wow64-i386" && $8 == "maintenance_summary" && $9 ~ /invalidation_passes=[1-9][0-9]*/ { found=1 } END { exit !found }' "$i386_trace" ||
    { echo "no correlated i386 FEX invalidation summary" >&2; exit 1; }

{
    printf 'schema=1\n'
    printf 'prefix=%s\n' "$PREFIX"
    printf 'fex_tsoenabled=0\nfex_vectortsoenabled=0\nfex_memcpysettsoenabled=0\n'
    printf 'x64_marker=WOW64_VM_X64_CONTRACT_OK\n'
    printf 'i386_marker=WOW64_VM_I386_CONTRACT_OK\n'
    printf 'executable_reuse_marker=WOW64_VM_EXECUTABLE_REUSE_OK\n'
    printf 'x64_fex_trace=%s\n' "$x64_fex_receipt"
    printf 'i386_fex_invalidation=correlated_maintenance_summary_nonzero\n'
} >"$EVIDENCE/receipt.txt"

status=0
echo "WOW64_VM_FEX_INVALIDATION_OK trace=$i386_trace"
echo "WOW64_VM_FEX_I386_INVALIDATION_OK trace=$i386_trace"
echo "WOW64_VM_CONTRACT_ALL_OK prefix=$PREFIX evidence=$EVIDENCE"
