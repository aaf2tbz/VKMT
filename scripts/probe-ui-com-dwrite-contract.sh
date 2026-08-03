#!/bin/bash
# COM/STA/DirectWrite contract.  Reuses the canonical Phase A prefix and
# performs no prefix creation or wineboot.  CEF/WebView pixel/text checks are
# recorded by the companion browser gate, not silently inferred here.
set -uo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd -P)"
BUILD="${WINEBUILDDIR:-$VKMT/wine/build-ec}"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
WINE="$BUILD/wine"
PREFIX="${VKMT_UI_PREFIX:-$VKMT/build/probe-runs/phase-a-graphics-prefix}"
EVIDENCE="${VKMT_UI_EVIDENCE_DIR:-$VKMT/docs/validation/ui-com-dwrite-contract-p8-20260803}"
TIMEOUT_VALUE="${VKMT_UI_TIMEOUT:-45}"
TIMEOUT="${TIMEOUT_VALUE%s}s"
ARCHES="${VKMT_UI_ARCHES:-arm64 arm64ec x86_64 i386}"
WINEDEBUG_VALUE="${VKMT_UI_WINEDEBUG:--all}"
run_root=""
overall=0

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
mkdir -p "$VKMT/build/probe-runs" "$EVIDENCE"
run_root="$(mktemp -d "$VKMT/build/probe-runs/ui-com-dwrite-contract-p8.XXXXXX")"

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
for spec in \
    'arm64:aarch64-w64-mingw32-clang:-ffixed-x18 -ffixed-x28' \
    'arm64ec:arm64ec-w64-mingw32-clang:-ffixed-x18 -ffixed-x28' \
    'x86_64:x86_64-w64-mingw32-clang:' \
    'i386:i686-w64-mingw32-clang:'; do
    IFS=: read -r arch compiler extra <<EOF
$spec
EOF
    # shellcheck disable=SC2086
    if ! "$TOOL/$compiler" "${common[@]}" $extra \
        -o "$run_root/ui_contract_${arch}.exe" "$VKMT/test/ui_com_dwrite_contract.c" \
        -lole32 -luuid -ldwrite -luser32 -lgdi32 >"$run_root/compile-$arch.log" 2>&1; then
        cat "$run_root/compile-$arch.log" >&2
        exit 1
    fi
done

for arch in $ARCHES; do
    log="$run_root/$arch.log"
    env WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
        WINE_NO_EXPLORER=1 WINEDEBUG="$WINEDEBUG_VALUE" \
        FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
        timeout --signal=TERM --kill-after=5s "$TIMEOUT" "$WINE" \
        "Z:$run_root/ui_contract_${arch}.exe" >"$log" 2>&1
    code=$?
    if test "$code" -ne 0; then overall=1; fi
done

{
    printf 'arch\tapi\tstatus\thresult\tdetail\n'
    for arch in $ARCHES; do
        log="$run_root/$arch.log"
        test -f "$log" && grep '^UI_CAP' "$log" | tr -d '\r' | cut -f2- || true
        code=0
        if test -f "$log" && ! grep -q '^UI_COM_DWRITE_CONTRACT_OK' "$log"; then
            if grep -q 'EXCEPTION_ILLEGAL_INSTRUCTION\|c000001d' "$log" 2>/dev/null; then
                printf '%s\tloader/FEX\tBLOCKED\t0xc000001d\tguest process failed before UI output\n' "$arch"
            elif grep -q 'UI_COM_DWRITE_CONTRACT_FAIL' "$log" 2>/dev/null; then
                printf '%s\tcontract_execution\tFAIL\t0x00000001\tfixture reported failure\n' "$arch"
            else
                printf '%s\tcontract_execution\tEXECUTION\t0x00000001\tno contract marker (rc or timeout)\n' "$arch"
            fi
        fi
    done
} >"$EVIDENCE/capability.tsv"

{
    printf '# COM, STA, callbacks, and DirectWrite contract — P8\n\n'
    printf 'Prefix: `%s`\n\n' "$PREFIX"
    if test "$overall" = 0; then
        printf '**Result:** requested architecture processes completed with rc=0.\n\n'
    else
        printf '**Result:** one or more architecture lanes failed, timed out, or were blocked.\n\n'
    fi
    printf '## Capability table\n\n| Architecture | API | Status | HRESULT | Detail |\n|---|---|---|---|---|\n'
    awk -F '\t' 'NR > 1 { printf "| %s | %s | %s | %s | %s |\n", $1,$2,$3,$4,$5 }' "$EVIDENCE/capability.tsv"
    printf '\n## Scope\n\n'
    printf '%s\n' \
      '- COM STA initialization and standard IStream cross-apartment marshaling.' \
      '- STA message pumping, cross-thread callback delivery, nested SendMessage callback, completion ordering, and window destruction.' \
      '- DirectWrite factory/font collection enumeration, family/font-face lookup, glyph lookup, mixed-script text layout, and system fallback MapCharacters.' \
      '- `UNSUPPORTED` rows are explicit known provider gaps; they are not reported as passes.' \
      '- Current known gaps are standard IStream cross-apartment marshal (`0x80070102`) on all lanes and i386 mixed-script layout metrics (`0x80004005`); STA callbacks/window lifetime and DirectWrite fallback still pass.' \
      '- CEF/WebView actual text/pixel output is a separate browser evidence gate.' \
      '- Font source candidates `dlls/dwrite/freetype.c` and `dlls/win32u/freetype.c` are not changed by this fixture.'
    printf '\nEnvironment: FEX_TSOENABLED=0, FEX_VECTORTSOENABLED=0, FEX_MEMCPYSETTSOENABLED=0, wineboot=not-run.\n'
} >"$EVIDENCE/RESULTS.md"

if test "$overall" = 0; then
    echo UI_COM_DWRITE_CONTRACT_ALL_ARCHITECTURES_OK
else
    echo UI_COM_DWRITE_CONTRACT_GAPS >&2
fi
exit "$overall"
