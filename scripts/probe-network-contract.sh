#!/bin/bash
# Deterministic WinSock contract: reuse the receipt-backed Phase A prefix.
# This runner never creates a prefix or invokes wineboot.  Each architecture
# has a hard timeout so a provider regression cannot strand the all-arch gate.
set -uo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd -P)"
BUILD="${WINEBUILDDIR:-$VKMT/wine/build-ec}"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
WINE="$BUILD/wine"
PREFIX="${VKMT_NETWORK_PREFIX:-$VKMT/build/probe-runs/phase-a-graphics-prefix}"
EVIDENCE="${VKMT_NETWORK_EVIDENCE_DIR:-$VKMT/docs/validation/network-contract-p8-20260803}"
TIMEOUT_VALUE="${VKMT_NETWORK_TIMEOUT:-45}"
TIMEOUT="${TIMEOUT_VALUE%s}s"
WINEDEBUG_VALUE="${VKMT_NETWORK_WINEDEBUG:--all}"
run_root=""
overall=0
names=()
codes=()

usage() { echo "usage: $0 [--prefix ABSOLUTE_PATH] [--evidence-dir ABSOLUTE_PATH]" >&2; exit 2; }
while test "$#" -gt 0; do
    case "$1" in
        --prefix) test "$#" -ge 2 || usage; PREFIX=$2; shift 2;;
        --evidence-dir) test "$#" -ge 2 || usage; EVIDENCE=$2; shift 2;;
        *) usage;;
    esac
done

case "$PREFIX" in /*) ;; *) echo "prefix must be absolute: $PREFIX" >&2; exit 2;; esac
case "$EVIDENCE" in /*) ;; *) echo "evidence directory must be absolute: $EVIDENCE" >&2; exit 2;; esac
test -x "$WINE" || { echo "missing Wine runtime: $WINE" >&2; exit 1; }
test -d "$PREFIX/.vkmt" || { echo "prefix is not receipt-backed: $PREFIX" >&2; exit 1; }
test -f "$VKMT/test/network_contract.c" || { echo "missing network fixture" >&2; exit 1; }
mkdir -p "$VKMT/build/probe-runs" "$EVIDENCE"
run_root="$(mktemp -d "$VKMT/build/probe-runs/network-contract-p8.XXXXXX")"

cleanup()
{
    status=$?
    if test -n "$run_root" && test -d "$run_root"; then
        find "$run_root" -maxdepth 1 -type f \( -name '*.log' -o -name '*.tsv' -o -name '*.txt' \) \
            -exec cp -p {} "$EVIDENCE/" \; 2>/dev/null || true
    fi
    printf 'status=%s\n' "$status" >"$EVIDENCE/status.txt"
    case "$run_root" in "$VKMT/build/probe-runs"/*) rm -rf "$run_root";; esac
    exit "$status"
}
trap cleanup EXIT

if ! "$VKMT/scripts/vkmt-prefix" verify --prefix "$PREFIX" >"$run_root/prefix-verify.log" 2>&1; then
    cat "$run_root/prefix-verify.log" >&2
    exit 1
fi

common=(-std=c11 -O2 -Wall -Wextra -Werror -I"$TOOL/../generic-w64-mingw32/include")
if ! "$TOOL/aarch64-w64-mingw32-clang" "${common[@]}" -ffixed-x18 -ffixed-x28 \
    -o "$run_root/network_contract_arm64.exe" "$VKMT/test/network_contract.c" -lws2_32 \
    >"$run_root/compile-arm64.log" 2>&1; then cat "$run_root/compile-arm64.log" >&2; exit 1; fi
if ! "$TOOL/arm64ec-w64-mingw32-clang" "${common[@]}" -ffixed-x18 -ffixed-x28 \
    -o "$run_root/network_contract_arm64ec.exe" "$VKMT/test/network_contract.c" -lws2_32 \
    >"$run_root/compile-arm64ec.log" 2>&1; then cat "$run_root/compile-arm64ec.log" >&2; exit 1; fi
if ! "$TOOL/x86_64-w64-mingw32-clang" "${common[@]}" \
    -o "$run_root/network_contract_x86_64.exe" "$VKMT/test/network_contract.c" -lws2_32 \
    >"$run_root/compile-x86_64.log" 2>&1; then cat "$run_root/compile-x86_64.log" >&2; exit 1; fi
if ! "$TOOL/i686-w64-mingw32-clang" "${common[@]}" \
    -o "$run_root/network_contract_i386.exe" "$VKMT/test/network_contract.c" -lws2_32 \
    >"$run_root/compile-i386.log" 2>&1; then cat "$run_root/compile-i386.log" >&2; exit 1; fi

run_arch()
{
    name=$1
    log="$run_root/$name.log"
    env WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
        WINE_NO_EXPLORER=1 WINEDEBUG="$WINEDEBUG_VALUE" \
        FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
        timeout --signal=TERM --kill-after=5s "$TIMEOUT" "$WINE" \
        "Z:$run_root/network_contract_${name}.exe" >"$log" 2>&1
    code=$?
    names+=("$name")
    codes+=("$code")
    if test "$code" -ne 0; then overall=1; fi
}

run_arch arm64
run_arch arm64ec
run_arch x86_64
run_arch i386

{
    printf 'arch\tapi\tstatus\terror\tdetail\n'
    for name in arm64 arm64ec x86_64 i386; do
        log="$run_root/$name.log"
        if test -f "$log"; then
            grep '^NETWORK_CAP' "$log" | tr -d '\r' | cut -f2- || true
        fi
        code=0
        for i in "${!names[@]}"; do test "${names[$i]}" = "$name" && code="${codes[$i]}"; done
        if test "$code" -ne 0; then
            if grep -q 'EXCEPTION_ILLEGAL_INSTRUCTION\|c000001d' "$log" 2>/dev/null; then
                printf '%s\tloader/FEX\tBLOCKED\t0xc000001d\tguest process failed before fixture output (rc=%s)\n' "$name" "$code"
            elif test "$code" = 124 || test "$code" = 137; then
                printf '%s\tloader/FEX\tTIMEOUT\t0x00000102\tfixture exceeded %s\n' "$name" "$TIMEOUT"
            else
                printf '%s\tcontract_execution\tFAIL\t0x%08x\tfixture rc=%s\n' "$name" "$code" "$code"
            fi
        fi
    done
} >"$EVIDENCE/capability.tsv"

{
    printf '# WinSock contract — P8\n\n'
    printf 'Prefix: `%s`\n\n' "$PREFIX"
    printf 'The fixture uses only loopback and `localhost`; it performs no external DNS or network access.\n\n'
    if test "$overall" = 0; then
        printf '**Result:** all four architecture processes completed with rc=0.\n\n'
    else
        printf '**Result:** execution completed or was bounded, but one or more architecture lanes failed, timed out, or were blocked before producing a contract result.\n\n'
    fi
    printf '## Capability table\n\n| Architecture | API | Status | Error | Detail |\n|---|---|---|---|---|\n'
    awk -F '\t' 'NR > 1 { printf "| %s | %s | %s | %s | %s |\n", $1,$2,$3,$4,$5 }' "$EVIDENCE/capability.tsv"
    printf '\n## Scope\n\n'
    printf '%s\n' \
      '- IPv4/IPv6 loopback, offline localhost address enumeration, and address ordering.' \
      '- Nonblocking connect/SO_ERROR, select, WSAPoll, WSAEventSelect notification/rearm.' \
      '- Overlapped WSARecv with IOCP completion lifetime and parallel connect/send/close races.' \
      '- `UNSUPPORTED` rows are explicit provider capability results and are not silently converted to passes.' \
      '- TLS trust, fragmentation, proxy, COM, callback, and DirectWrite contracts are separate gates.'
    printf '\nEnvironment: FEX_TSOENABLED=0, FEX_VECTORTSOENABLED=0, FEX_MEMCPYSETTSOENABLED=0, wineboot=not-run.\n'
} >"$EVIDENCE/RESULTS.md"

if test "$overall" = 0; then
    echo NETWORK_CONTRACT_ALL_ARCHITECTURES_OK
else
    echo NETWORK_CONTRACT_ALL_ARCHITECTURES_GAPS >&2
fi
exit "$overall"
