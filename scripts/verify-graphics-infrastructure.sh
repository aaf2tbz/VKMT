#!/bin/bash
# Verify the P8 graphics execution contract without creating or modifying a
# prefix. This is an infrastructure gate, not a behavioral renderer test.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd -P)"
BUILD="${WINEBUILDDIR:-$VKMT/wine/build-ec}"
PREFIX="${VKMT_GRAPHICS_PREFIX:-$VKMT/build/probe-runs/phase-a-graphics-prefix}"
EVIDENCE="${VKMT_GRAPHICS_INFRA_EVIDENCE:-$VKMT/docs/validation/graphics-infrastructure-p8}"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"

die() { echo "graphics-infrastructure: $*" >&2; exit 1; }
sha() { shasum -a 256 "$1" | awk '{print $1}'; }
machine() {
    "$TOOL/llvm-readobj" --file-headers "$1" |
        awk '/Machine:/ {print $2; exit}'
}
require_file() { test -f "$1" || die "missing: ${1#$VKMT/}"; }
require_machine() {
    local expected=$1 file=$2 actual
    actual="$(machine "$file")"
    test "$actual" = "$expected" ||
        die "wrong machine for ${file#$VKMT/}: $actual (expected $expected)"
}

test "$(uname -m)" = arm64 || die "host must be native ARM64"
test -x "$BUILD/wine" || die "missing Wine host"
test -x "$BUILD/server/wineserver" || die "missing wineserver"
test -d "$PREFIX/.vkmt" || die "prefix is not receipt-backed: $PREFIX"
for file in "$PREFIX/.vkmt/receipt.json" \
            "$PREFIX/.vkmt/staged-files.manifest" \
            "$PREFIX/.vkmt/environment.sh"; do
    require_file "$file"
done

profile="$(python3 - "$PREFIX/.vkmt/receipt.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f).get("profile", ""))
PY
)"
case "$profile" in
    graphics|full) ;;
    *) die "prefix profile is $profile, expected graphics or full" ;;
esac

# The prepared environment is the source of truth for launchers. A probe may
# repeat these assignments for clarity, but may not override them with 1.
for option in FEX_TSOENABLED FEX_VECTORTSOENABLED FEX_MEMCPYSETTSOENABLED; do
    grep -Eq "^export ${option}=0$" "$PREFIX/.vkmt/environment.sh" ||
        die "prefix environment does not force ${option}=0"
done
export FEX_TSOENABLED=0
export FEX_VECTORTSOENABLED=0
export FEX_MEMCPYSETTSOENABLED=0

# Only these scripts are graphics acceptance launchers. Java software-ordering
# diagnostics are outside this phase and are reported separately.
acceptance_scripts=(
    "$VKMT/scripts/probe-d3d11-graphics-contract.sh"
    "$VKMT/scripts/probe-d3d12-graphics-contract.sh"
    "$VKMT/scripts/probe-d3d9-contract.sh"
    "$VKMT/scripts/probe-dxmt-arm64ec.sh"
    "$VKMT/scripts/probe-opengl-extended-contract.sh"
)
for script in "${acceptance_scripts[@]}"; do
    require_file "$script"
    for option in FEX_TSOENABLED FEX_VECTORTSOENABLED FEX_MEMCPYSETTSOENABLED; do
        grep -Eq "${option}=0" "$script" ||
            die "graphics script does not force ${option}=0: ${script#$VKMT/}"
        if grep -Eq "${option}=1" "$script"; then
            die "graphics script enables ${option}: ${script#$VKMT/}"
        fi
    done
done

require_file "$BUILD/dlls/xtajit/aarch64-windows/xtajit.dll"
require_file "$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll"
require_machine IMAGE_FILE_MACHINE_ARM64 \
    "$BUILD/dlls/xtajit/aarch64-windows/xtajit.dll"
require_machine IMAGE_FILE_MACHINE_ARM64EC \
    "$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll"

moltenvk="$BUILD/dlls/win32u/libMoltenVK.dylib"
require_file "$moltenvk"
test "$(/usr/bin/lipo -archs "$moltenvk")" = 'x86_64 arm64' ||
    die "promoted MoltenVK is not the expected universal dylib"

artifacts=(
    "$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/aarch64/d3d9.dll"
    "$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/aarch64/d3d11.dll"
    "$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/aarch64/dxgi.dll"
    "$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/arm64ec/d3d9.dll"
    "$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/arm64ec/d3d11.dll"
    "$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/arm64ec/dxgi.dll"
    "$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/x32/d3d9.dll"
    "$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/x32/d3d11.dll"
    "$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/x32/dxgi.dll"
    "$VKMT/third_party/vkd3d-proton/install-arm64/bin/d3d12.dll"
    "$VKMT/third_party/vkd3d-proton/install-arm64/bin/d3d12core.dll"
    "$VKMT/third_party/vkd3d-proton/install-arm64ec/bin/d3d12.dll"
    "$VKMT/third_party/vkd3d-proton/install-arm64ec/bin/d3d12core.dll"
    "$VKMT/third_party/vkd3d-proton/install-win32/bin/d3d12.dll"
    "$VKMT/third_party/vkd3d-proton/install-win32/bin/d3d12core.dll"
    "$BUILD/dxmt-v0.80/aarch64-windows/d3d10core.dll"
    "$BUILD/dxmt-v0.80/aarch64-windows/d3d11.dll"
    "$BUILD/dxmt-v0.80/aarch64-windows/dxgi.dll"
    "$BUILD/dxmt-v0.80/aarch64-windows/winemetal.dll"
    "$BUILD/dxmt-v0.80/aarch64-unix/winemetal.so"
    "$BUILD/dxmt-v0.80/aarch64-unix/libunwind.1.dylib"
)
for file in "${artifacts[@]}"; do
    require_file "$file"
done

for file in "$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/aarch64"/*.dll; do
    require_machine IMAGE_FILE_MACHINE_ARM64 "$file"
done
for file in "$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/arm64ec"/*.dll; do
    require_machine IMAGE_FILE_MACHINE_ARM64EC "$file"
done
for file in "$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/x32"/*.dll; do
    require_machine IMAGE_FILE_MACHINE_I386 "$file"
done
for file in "$VKMT/third_party/vkd3d-proton/install-arm64/bin"/*.dll; do
    require_machine IMAGE_FILE_MACHINE_ARM64 "$file"
done
for file in "$VKMT/third_party/vkd3d-proton/install-arm64ec/bin"/*.dll; do
    require_machine IMAGE_FILE_MACHINE_ARM64EC "$file"
done
for file in "$VKMT/third_party/vkd3d-proton/install-win32/bin"/*.dll; do
    require_machine IMAGE_FILE_MACHINE_I386 "$file"
done
for file in "$BUILD/dxmt-v0.80/aarch64-windows"/*.dll; do
    require_machine IMAGE_FILE_MACHINE_ARM64EC "$file"
done

mkdir -p "$EVIDENCE"
{
    printf 'key\tvalue\n'
    printf 'prefix\t%s\n' "$PREFIX"
    printf 'profile\t%s\n' "$profile"
    printf 'host\t%s\n' "$(uname -m)"
    printf 'fex_tsoenabled\t%s\n' "$FEX_TSOENABLED"
    printf 'fex_vectortsoenabled\t%s\n' "$FEX_VECTORTSOENABLED"
    printf 'fex_memcpysettsoenabled\t%s\n' "$FEX_MEMCPYSETTSOENABLED"
    printf 'promoted_moltenvk_arches\t%s\n' "$(/usr/bin/lipo -archs "$moltenvk")"
    printf 'promoted_moltenvk_sha256\t%s\n' "$(sha "$moltenvk")"
    for file in "${artifacts[@]}"; do
        if [[ "$file" == *.dll ]]; then
            arch="$(machine "$file")"
        else
            arch="$(/usr/bin/lipo -archs "$file" 2>/dev/null || file "$file")"
        fi
        printf 'artifact\t%s\t%s\t%s\n' \
            "${file#$VKMT/}" "$arch" "$(sha "$file")"
    done
} >"$EVIDENCE/capability.tsv"

{
    printf '# Graphics infrastructure contract — P8\n\n'
    printf 'Prefix: `%s`\n\n' "$PREFIX"
    printf -- '- Canonical receipt-backed prefix verified without Wineboot.\n'
    printf -- '- Active graphics acceptance scripts force all FEX TSO modes to zero.\n'
    printf -- '- Promoted FEX, DXVK, vkd3d-proton, DXMT, and MoltenVK artifacts are present and architecture-checked.\n'
    printf -- '- This gate verifies staging integrity; it does not substitute for behavioral graphics contracts.\n\n'
    printf '**GRAPHICS_INFRASTRUCTURE_P8_OK**\n'
} >"$EVIDENCE/RESULTS.md"

printf 'GRAPHICS_INFRASTRUCTURE_P8_OK\n'
