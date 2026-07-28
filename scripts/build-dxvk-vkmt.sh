#!/bin/bash
# Build a pinned DXVK PE runtime into the active VKMT tree. This does not
# rebuild Wine and defaults to the Phase 5 i386 target.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$VKMT/third_party/dxvk"
OUT="$SRC/runtime/dxvk-vkmt-1a5919b"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
VULKAN_HEADERS="$VKMT/third_party/vkd3d-proton/khronos/Vulkan-Headers/include"
SPIRV_HEADERS="$VKMT/third_party/vkd3d-proton/khronos/SPIRV-Headers/include"
ARCH="${1:-32}"

test -d "$SRC/.git" || { echo 'DXVK source is missing' >&2; exit 1; }
test -x "$TOOL/i686-w64-mingw32-clang++" || { echo 'In-tree LLVM-MinGW is missing' >&2; exit 1; }
test -d "$VULKAN_HEADERS/vulkan" || { echo 'In-tree Vulkan headers are missing' >&2; exit 1; }
test -d "$SPIRV_HEADERS/spirv" || { echo 'In-tree SPIR-V headers are missing' >&2; exit 1; }

case "$ARCH" in
  32) pairs=('32 i686') ;;
  64) pairs=('64 x86_64') ;;
  all) pairs=('32 i686' '64 x86_64') ;;
  *) echo "Usage: $0 [32|64|all]" >&2; exit 2 ;;
esac

mkdir -p "$OUT"
for pair in "${pairs[@]}"; do
  set -- $pair
  bits=$1
  triple=$2
  build="$OUT/build.clang.$bits"
  cross="$OUT/build-vkmt-win$bits.txt"
  cat >"$cross" <<EOF
[binaries]
c = '$TOOL/$triple-w64-mingw32-clang'
cpp = '$TOOL/$triple-w64-mingw32-clang++'
ar = '$TOOL/$triple-w64-mingw32-ar'
strip = '$TOOL/$triple-w64-mingw32-strip'
windres = '$TOOL/$triple-w64-mingw32-windres'

[built-in options]
c_args = ['-I$VULKAN_HEADERS', '-I$SPIRV_HEADERS']
cpp_args = ['-I$VULKAN_HEADERS', '-I$SPIRV_HEADERS']

[properties]
needs_exe_wrapper = true

[host_machine]
system = 'windows'
cpu_family = '$([ "$bits" = 32 ] && echo x86 || echo x86_64)'
cpu = '$triple'
endian = 'little'
EOF
  if test -f "$build/meson-private/coredata.dat"; then
    meson setup "$build" "$SRC" --cross-file "$cross" --reconfigure \
      --buildtype release --prefix "$OUT" --bindir "x$bits" --libdir "x$bits" \
      -Db_ndebug=if-release
  else
    meson setup "$build" "$SRC" --cross-file "$cross" \
      --buildtype release --prefix "$OUT" --bindir "x$bits" --libdir "x$bits" \
      -Db_ndebug=if-release
  fi
  meson compile -C "$build" -j "${JOBS:-8}"
  meson install -C "$build"
done
