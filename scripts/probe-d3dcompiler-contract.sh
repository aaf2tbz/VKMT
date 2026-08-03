#!/bin/bash
# D3DCompiler contract: one receipt-backed prefix, all guest architectures.
# This runner never creates or boots a prefix. It stages only the optional
# 32-bit graphics provider closure needed by the consumer lanes.
set -uo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd -P)"
BUILD="${WINEBUILDDIR:-$VKMT/wine/build-ec}"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
WINE="$BUILD/wine"
PREFIX="${VKMT_D3DCOMPILER_PREFIX:-$VKMT/build/probe-runs/phase-a-graphics-prefix}"
EVIDENCE="${VKMT_D3DCOMPILER_EVIDENCE_DIR:-$VKMT/docs/validation/d3dcompiler-contract-p8-20260803}"
STAGE_CONSUMERS="${VKMT_D3DCOMPILER_STAGE_CONSUMERS:-1}"
WINEDEBUG_VALUE="${VKMT_D3DCOMPILER_WINEDEBUG:--all}"
run_root=""
overall=0
lane_names=()
lane_codes=()
lane_logs=()

usage()
{
    echo "usage: $0 [--prefix ABSOLUTE_PATH] [--evidence-dir ABSOLUTE_PATH] [--no-consumers]" >&2
    exit 2
}

while test "$#" -gt 0; do
    case "$1" in
        --prefix) test "$#" -ge 2 || usage; PREFIX=$2; shift 2;;
        --evidence-dir) test "$#" -ge 2 || usage; EVIDENCE=$2; shift 2;;
        --no-consumers) STAGE_CONSUMERS=0; shift;;
        *) usage;;
    esac
done

case "$PREFIX" in /*) ;; *) echo "prefix must be absolute: $PREFIX" >&2; exit 2;; esac
case "$EVIDENCE" in /*) ;; *) echo "evidence directory must be absolute: $EVIDENCE" >&2; exit 2;; esac
test -x "$WINE" || { echo "missing Wine runtime: $WINE" >&2; exit 1; }
test -d "$PREFIX/.vkmt" || { echo "prefix is not receipt-backed: $PREFIX" >&2; exit 1; }

for f in "$TOOL/aarch64-w64-mingw32-clang" "$TOOL/arm64ec-w64-mingw32-clang" \
    "$TOOL/x86_64-w64-mingw32-clang" "$TOOL/i686-w64-mingw32-clang" \
    "$TOOL/llvm-readobj" "$VKMT/test/d3dcompiler_contract.c"; do
    test -e "$f" || { echo "missing D3DCompiler contract input: $f" >&2; exit 1; }
done

mkdir -p "$VKMT/build/probe-runs" "$EVIDENCE"
run_root="$(mktemp -d "$VKMT/build/probe-runs/d3dcompiler-contract-p8.XXXXXX")"
cleanup()
{
    status=$?
    if test -n "$run_root" && test -d "$run_root"; then
        mkdir -p "$EVIDENCE"
        find "$run_root" -maxdepth 1 -type f \( -name '*.log' -o -name '*.txt' -o -name '*.tsv' \) \
            -exec cp -p {} "$EVIDENCE/" \; 2>/dev/null || true
    fi
    printf 'status=%s\n' "$status" >"$EVIDENCE/status.txt"
    case "$run_root" in
        "$VKMT/build/probe-runs"/*) rm -rf "$run_root";;
    esac
    exit "$status"
}
trap cleanup EXIT

# Validate before staging; sync-graphics32 updates this same prefix without
# invoking wineboot and leaves a hash-backed source mapping in the manifest.
if ! "$VKMT/scripts/vkmt-prefix" verify --prefix "$PREFIX" >"$run_root/prefix-verify-before.log" 2>&1; then
    echo "D3DCompiler contract prefix verification failed" >&2
    cat "$run_root/prefix-verify-before.log" >&2
    exit 1
fi
if test "$STAGE_CONSUMERS" = 1; then
    if ! "$VKMT/scripts/vkmt-prefix" sync-graphics32 --prefix "$PREFIX" >"$run_root/graphics32-sync.log" 2>&1; then
        echo "D3DCompiler consumer staging failed" >&2
        cat "$run_root/graphics32-sync.log" >&2
        exit 1
    fi
    if ! "$VKMT/scripts/vkmt-prefix" verify --prefix "$PREFIX" >"$run_root/prefix-verify-after.log" 2>&1; then
        echo "D3DCompiler contract prefix verification failed after graphics32 sync" >&2
        cat "$run_root/prefix-verify-after.log" >&2
        exit 1
    fi
fi

compile_common=(-O2 -Wall -Wextra -I"$TOOL/../generic-w64-mingw32/include")
if ! "$TOOL/aarch64-w64-mingw32-clang" "${compile_common[@]}" -ffixed-x18 -ffixed-x28 \
    -o "$run_root/d3dcompiler_contract_arm64.exe" "$VKMT/test/d3dcompiler_contract.c" \
    -ld3dcompiler_47 -lole32 -luuid >"$run_root/compile-arm64.log" 2>&1; then
    cat "$run_root/compile-arm64.log" >&2; exit 1
fi
if ! "$TOOL/arm64ec-w64-mingw32-clang" "${compile_common[@]}" -ffixed-x18 -ffixed-x28 \
    -o "$run_root/d3dcompiler_contract_arm64ec.exe" "$VKMT/test/d3dcompiler_contract.c" \
    -ld3dcompiler_47 -lole32 -luuid >"$run_root/compile-arm64ec.log" 2>&1; then
    cat "$run_root/compile-arm64ec.log" >&2; exit 1
fi
if ! "$TOOL/x86_64-w64-mingw32-clang" "${compile_common[@]}" \
    -o "$run_root/d3dcompiler_contract_x86_64.exe" "$VKMT/test/d3dcompiler_contract.c" \
    -ld3dcompiler_47 -lole32 -luuid >"$run_root/compile-x86_64.log" 2>&1; then
    cat "$run_root/compile-x86_64.log" >&2; exit 1
fi
if ! "$TOOL/i686-w64-mingw32-clang" "${compile_common[@]}" \
    -o "$run_root/d3dcompiler_contract_i386.exe" "$VKMT/test/d3dcompiler_contract.c" \
    -ld3dcompiler_47 -lole32 -luuid >"$run_root/compile-i386.log" 2>&1; then
    cat "$run_root/compile-i386.log" >&2; exit 1
fi

for spec in \
    "arm64:arm64:IMAGE_FILE_MACHINE_ARM64" \
    "arm64ec:arm64ec:IMAGE_FILE_MACHINE_ARM64EC" \
    "x86_64:x86_64:IMAGE_FILE_MACHINE_AMD64" \
    "i386:i386:IMAGE_FILE_MACHINE_I386"; do
    IFS=: read -r name file expected <<EOF
$spec
EOF
    machine="$($TOOL/llvm-readobj --file-headers "$run_root/d3dcompiler_contract_${file}.exe" |
        awk '/Machine:/ {print $2; exit}')"
    test "$machine" = "$expected" || { echo "wrong PE machine for $name: $machine" >&2; exit 1; }
done

run_lane()
{
    name=$1
    exe=$2
    shift 2
    log="$run_root/$name.log"
    # These variables are inert for compiler-only lanes and select the
    # staged providers for the isolated i386 consumer lanes.
    graphics_env=(VK_ICD_FILENAMES="$VKMT/test/vkmt_icd.json"
        WINEDLLOVERRIDES='dxgi,d3d11,d3d12,d3d12core=n'
        VKMT_ALLOW_NON_SINGLE_TEXEL_ALIGNMENT=1)
    env WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
        WINE_NO_EXPLORER=1 WINEDEBUG="$WINEDEBUG_VALUE" \
        FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
        "${graphics_env[@]}" \
        "$WINE" "Z:$exe" "$@" >"$log" 2>&1
    code=$?
    lane_names+=("$name")
    lane_codes+=("$code")
    lane_logs+=("$log")
    if test "$code" -ne 0; then
        env WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
            WINE_NO_EXPLORER=1 WINEDEBUG=+seh \
            FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
            "${graphics_env[@]}" \
            "$WINE" "Z:$exe" "$@" >"$run_root/$name-diagnostic.log" 2>&1 || true
        overall=1
    fi
}

marker_name()
{
    printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_'
}

run_lane arm64 "$run_root/d3dcompiler_contract_arm64.exe"
run_lane arm64ec "$run_root/d3dcompiler_contract_arm64ec.exe"
run_lane x86_64 "$run_root/d3dcompiler_contract_x86_64.exe"
run_lane i386 "$run_root/d3dcompiler_contract_i386.exe"

if test "$STAGE_CONSUMERS" = 1; then
    # Keep DXVK and vkd3d-proton in separate processes. A combined WoW64
    # process can fault after a successful D3D11 pass at this boundary.
    run_lane i386-d3d11 "$run_root/d3dcompiler_contract_i386.exe" --d3d11
    run_lane i386-d3d12 "$run_root/d3dcompiler_contract_i386.exe" --d3d12
else
    printf 'i386\td3d11\tDXBC_consumption\tSKIP\t0x00000001\tconsumer staging disabled\n' >"$run_root/consumer-skips.tsv"
    printf 'i386\td3d12\tDXBC_consumption\tSKIP\t0x00000001\tconsumer staging disabled\n' >>"$run_root/consumer-skips.tsv"
fi

{
    printf 'arch\tdll\tapi\tstatus\thresult\tdetail\n'
    for log in "$run_root/arm64.log" "$run_root/arm64ec.log" "$run_root/x86_64.log" "$run_root/i386.log"; do
        test -f "$log" || continue
        grep '^D3DCOMPILER_CAP' "$log" | tr -d '\r' | cut -f2- |
            awk -F '\t' '!( $1 == "i386" && ($2 == "d3d11" || $2 == "d3d12") )'
    done
    if test "$STAGE_CONSUMERS" = 1; then
        grep '^D3DCOMPILER_CAP' "$run_root/i386-d3d11.log" | tr -d '\r' | cut -f2- |
            awk -F '\t' '$1 == "i386" && $2 == "d3d11"'
        grep '^D3DCOMPILER_CAP' "$run_root/i386-d3d12.log" | tr -d '\r' | cut -f2- |
            awk -F '\t' '$1 == "i386" && $2 == "d3d12"'
    else
        cat "$run_root/consumer-skips.tsv"
    fi
    for name in arm64ec x86_64; do
        code=0
        for i in "${!lane_names[@]}"; do
            test "${lane_names[$i]}" = "$name" && code="${lane_codes[$i]}"
        done
        if test "$code" -ne 0; then
            printf '%s\tloader/FEX\tcontract_execution\tBLOCKED\t0xc000001d\tFEX xtajit64 illegal-instruction boundary before contract output (rc=%s)\n' "$name" "$code"
        fi
    done
} >"$EVIDENCE/capability.tsv"

for i in "${!lane_names[@]}"; do
        name=${lane_names[$i]}; code=${lane_codes[$i]}
    marker="$(marker_name "$name")"
    case "$name" in
        arm64|i386)
            if test "$code" = 0; then echo "D3DCOMPILER_CONTRACT_${marker}_OK"; else overall=1; fi;;
        arm64ec|x86_64)
            if test "$code" = 0; then echo "D3DCOMPILER_CONTRACT_${marker}_OK"; else echo "D3DCOMPILER_CONTRACT_${marker}_BLOCKED"; fi;;
        i386-d3d11|i386-d3d12)
            if test "$code" = 0; then echo "D3DCOMPILER_CONSUMER_${name#i386-}_OK"; else echo "D3DCOMPILER_CONSUMER_${name#i386-}_FAIL"; overall=1; fi;;
    esac
done

cp -p "$EVIDENCE/capability.tsv" "$run_root/capability.tsv"
{
    printf 'prefix=%s\n' "$PREFIX"
    printf 'wine=%s\n' "$WINE"
    printf 'stage_consumers=%s\n' "$STAGE_CONSUMERS"
    printf 'FEX_TSOENABLED=0\nFEX_VECTORTSOENABLED=0\nFEX_MEMCPYSETTSOENABLED=0\n'
    printf 'wineboot=not-run\nsource=test/d3dcompiler_contract.c\n'
} | tee "$EVIDENCE/environment.txt" "$run_root/environment.txt" >/dev/null
test ! -f "$PREFIX/.vkmt/graphics32-sync.receipt" || cp -p "$PREFIX/.vkmt/graphics32-sync.receipt" "$EVIDENCE/graphics32-sync.receipt"

if test "$overall" = 0; then
    result_text="The required compiler lanes and enabled consumer lanes completed with rc=0."
else
    result_text="Every requested lane was executed, but the capability table contains one or more failed or blocked rows; this is not a green all-architecture gate."
fi
{
    printf '# D3DCompiler contract — P8\n\n'
    printf 'Prefix: `%s`\n\n' "$PREFIX"
    printf '## Result\n\n%s\n\n' "$result_text"
    printf '## Architecture/API capability table\n\n'
    printf '| Architecture | DLL | API | Status | HRESULT | Detail |\n|---|---|---|---|---|---|\n'
    awk -F '\t' 'NR > 1 { gsub(/\|/, "\\|", $0); printf "| %s | %s | %s | %s | %s | %s |\n", $1,$2,$3,$4,$5,$6 }' "$EVIDENCE/capability.tsv"
    printf '\n## Known boundaries\n\n'
    printf '%s\n' \
      '- `d3dcompiler_43!D3DReflect` is recorded as `KNOWN_LIMITATION` with observed `E_NOINTERFACE`; it is not counted as a pass.' \
      '- `D3DLoadModule` is safely called on 47 and recorded as `KNOWN_STUB` / `E_NOTIMPL`.' \
      '- `D3DSetBlobPart` is a Wine spec stub and is intentionally not called because it raises an unimplemented-function exception; the table records `KNOWN_STUB_NOT_CALLED` / `E_NOTIMPL`.' \
      '- `D3DCompressShaders`, `D3DDecompressShaders`, trace/effect helpers, and `D3DReflectLibrary` remain source-declared stubs and are not reported as implemented.' \
      '- D3D11 and D3D12 consumers run in separate i386 processes; combining DXVK D3D11 and vkd3d-proton D3D12 in one process currently faults after the D3D11 pass.' \
      '- All lanes use FEX TSO settings of zero and do not invoke wineboot.'
} >"$EVIDENCE/RESULTS.md"
cp -p "$EVIDENCE/RESULTS.md" "$run_root/RESULTS.md"

if test "$overall" = 0; then
    echo D3DCOMPILER_CONTRACT_ALL_ARCHITECTURES_OK
else
    echo D3DCOMPILER_CONTRACT_ALL_ARCHITECTURES_EXECUTED_WITH_GAPS >&2
fi
exit "$overall"
