#!/bin/bash
# Create or verify the versioned per-prefix graphics cache contract.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${WINEBUILDDIR:-$VKMT/wine/build-ec}"
PREFIX="${WINEPREFIX:-}"
MODE=stage
MAX_GENERATIONS="${VKMT_GPU_CACHE_GENERATIONS:-2}"

usage()
{
  echo "usage: $0 [--prefix PREFIX] [--verify-prefix PREFIX]" >&2
  exit 2
}

while test $# -gt 0; do
  case "$1" in
    --prefix) test $# -ge 2 || usage; PREFIX=$2; MODE=stage; shift 2 ;;
    --verify-prefix) test $# -ge 2 || usage; PREFIX=$2; MODE=verify; shift 2 ;;
    *) usage ;;
  esac
done

test -n "$PREFIX" || usage
case "$PREFIX" in /*) ;; *) echo "GPU cache prefix must be absolute: $PREFIX" >&2; exit 1 ;; esac
case "$MAX_GENERATIONS" in ''|*[!0-9]*) usage ;; esac
test "$MAX_GENERATIONS" -ge 1 || usage

CACHE_ROOT="$PREFIX/.vkmt/gpu-cache"
MANIFEST="$CACHE_ROOT/MANIFEST.tsv"

component_hash()
{
  component=$1
  shift
  found=0
  for path in "$@"; do test ! -f "$path" || found=1; done
  if test "$found" = 0; then
    printf 'absent\n'
    return
  fi
  for path in "$@"; do
    test -f "$path" || continue
    shasum -a 256 "$path"
  done | LC_ALL=C sort | shasum -a 256 | awk '{ print $1 }'
}

dxvk_hash="$(component_hash dxvk \
  "$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/arm64ec/dxgi.dll" \
  "$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/arm64ec/d3d11.dll" \
  "$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/aarch64/dxgi.dll" \
  "$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/aarch64/d3d11.dll" \
  "$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/x64/dxgi.dll" \
  "$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/x64/d3d11.dll" \
  "$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/x32/dxgi.dll" \
  "$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/x32/d3d11.dll")"
vkd3d_hash="$(component_hash vkd3d \
  "$VKMT/third_party/vkd3d-proton/install-arm64/bin/d3d12.dll" \
  "$VKMT/third_party/vkd3d-proton/install-arm64/bin/d3d12core.dll" \
  "$VKMT/third_party/vkd3d-proton/install-arm64ec/bin/d3d12.dll" \
  "$VKMT/third_party/vkd3d-proton/install-arm64ec/bin/d3d12core.dll" \
  "$VKMT/third_party/vkd3d-proton/install-win64/bin/d3d12.dll" \
  "$VKMT/third_party/vkd3d-proton/install-win64/bin/d3d12core.dll" \
  "$VKMT/third_party/vkd3d-proton/install-win32/bin/d3d12.dll" \
  "$VKMT/third_party/vkd3d-proton/install-win32/bin/d3d12core.dll")"
dxmt_hash="$(component_hash dxmt \
  "$BUILD/dxmt-v0.80/aarch64-unix/winemetal.so" \
  "$BUILD/dxmt-v0.80/aarch64-windows/winemetal.dll" \
  "$BUILD/dxmt-v0.80/i386-windows/winemetal.dll")"
moltenvk_hash="$(component_hash moltenvk \
  "$VKMT/third_party/MoltenVK/Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib")"
opengl_hash="$(component_hash opengl \
  "$BUILD/dlls/winemac.drv/metalsharp-opengl.dylib")"
macos_version="$(sw_vers -productVersion)"
macos_build="$(sw_vers -buildVersion)"
hardware_model="$(sysctl -n hw.model)"
gpu_chipset="$(system_profiler SPDisplaysDataType 2>/dev/null |
  awk -F ': ' '/Chipset Model:/ { print $2; exit }')"
metal_generation="$(system_profiler SPDisplaysDataType 2>/dev/null |
  awk -F ': ' '/Metal Support:/ { print $2; exit }')"
test -n "$gpu_chipset"
test -n "$metal_generation"

generation="$(printf '%s\n' \
  "schema=2" "dxvk=$dxvk_hash" "vkd3d=$vkd3d_hash" "dxmt=$dxmt_hash" \
  "moltenvk=$moltenvk_hash" "opengl=$opengl_hash" \
  "macos_version=$macos_version" "macos_build=$macos_build" \
  "hardware_model=$hardware_model" "gpu_chipset=$gpu_chipset" \
  "metal_generation=$metal_generation" |
  shasum -a 256 | awk '{print "v2-" substr($1, 1, 16)}')"
GEN_ROOT="$CACHE_ROOT/$generation"

verify()
{
  test -s "$MANIFEST"
  test "$(awk -F '\t' '$1 == "schema" { print $2 }' "$MANIFEST")" = 2
  test "$(awk -F '\t' '$1 == "generation" { print $2 }' "$MANIFEST")" = "$generation"
  for entry in \
      dxvk vkd3d dxmt/shaders dxmt/pipelines metalsharp/shaders \
      metalsharp/pipelines metal xdg logs; do
    test -d "$GEN_ROOT/$entry"
  done
  test "$(awk -F '\t' '$1 == "dxvk" { print $2 }' "$MANIFEST")" = "$dxvk_hash"
  test "$(awk -F '\t' '$1 == "vkd3d" { print $2 }' "$MANIFEST")" = "$vkd3d_hash"
  test "$(awk -F '\t' '$1 == "dxmt" { print $2 }' "$MANIFEST")" = "$dxmt_hash"
  test "$(awk -F '\t' '$1 == "moltenvk" { print $2 }' "$MANIFEST")" = "$moltenvk_hash"
  test "$(awk -F '\t' '$1 == "opengl" { print $2 }' "$MANIFEST")" = "$opengl_hash"
  test "$(awk -F '\t' '$1 == "macos_build" { print $2 }' "$MANIFEST")" = "$macos_build"
  test "$(awk -F '\t' '$1 == "hardware_model" { print $2 }' "$MANIFEST")" = "$hardware_model"
  test "$(awk -F '\t' '$1 == "gpu_chipset" { print $2 }' "$MANIFEST")" = "$gpu_chipset"
  test "$(awk -F '\t' '$1 == "metal_generation" { print $2 }' "$MANIFEST")" = "$metal_generation"
}

if test "$MODE" = verify; then
  verify
  echo "VKMT_GPU_CACHE_VERIFY_OK generation=$generation"
  exit 0
fi

mkdir -p "$CACHE_ROOT"
chmod 700 "$CACHE_ROOT"
for entry in \
    dxvk vkd3d dxmt/shaders dxmt/pipelines metalsharp/shaders \
    metalsharp/pipelines metal xdg logs; do
  mkdir -p "$GEN_ROOT/$entry"
  chmod 700 "$GEN_ROOT/$entry"
done

manifest_tmp="$(mktemp "$CACHE_ROOT/.manifest.XXXXXX")"
cleanup_tmp() { test ! -e "$manifest_tmp" || find "$manifest_tmp" -delete; }
trap cleanup_tmp EXIT
{
  printf 'schema\t2\n'
  printf 'generation\t%s\n' "$generation"
  printf 'dxvk\t%s\n' "$dxvk_hash"
  printf 'vkd3d\t%s\n' "$vkd3d_hash"
  printf 'dxmt\t%s\n' "$dxmt_hash"
  printf 'moltenvk\t%s\n' "$moltenvk_hash"
  printf 'opengl\t%s\n' "$opengl_hash"
  printf 'macos_version\t%s\n' "$macos_version"
  printf 'macos_build\t%s\n' "$macos_build"
  printf 'hardware_model\t%s\n' "$hardware_model"
  printf 'gpu_chipset\t%s\n' "$gpu_chipset"
  printf 'metal_generation\t%s\n' "$metal_generation"
} >"$manifest_tmp"
chmod 600 "$manifest_tmp"
mv -f "$manifest_tmp" "$MANIFEST"
trap - EXIT

# Retain the current generation and at most one rollback generation by default.
generation_count=0
while IFS= read -r old_generation; do
  test -n "$old_generation" || continue
  generation_count=$((generation_count + 1))
  test "$generation_count" -le "$MAX_GENERATIONS" && continue
  test "$old_generation" != "$GEN_ROOT" || continue
  case "$old_generation" in "$CACHE_ROOT"/v[12]-*) find "$old_generation" -depth -delete ;; esac
done < <(find "$CACHE_ROOT" -mindepth 1 -maxdepth 1 -type d \
  \( -name 'v1-*' -o -name 'v2-*' \) -print |
  awk -v current="$GEN_ROOT" '{ print ($0 == current ? "0\t" : "1\t") $0 }' |
  LC_ALL=C sort | cut -f2-)

verify
echo "VKMT_GPU_CACHE_STAGE_OK generation=$generation root=$GEN_ROOT"
