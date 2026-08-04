#!/bin/bash
# Build the ARM64 vkd3d-proton runtime with the in-tree LLVM-MinGW.
#
# The default GCC build can emit Windows ARM64 C++ TLS references through
# x18. VKMT's DXIL-SPIRV TLS shim avoids those references, and these fixed
# registers keep the remaining C/C++ code compatible with Wine's ARM64
# boundary. This installs the actual provider used by staging and probes.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd -P)"
SRC="$VKMT/third_party/vkd3d-proton"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
BUILD="${VKMT_VKD3D_ARM64_BUILD:-$SRC/build-vkmt-arm64-clang}"
STAGE="${VKMT_VKD3D_ARM64_STAGE:-$SRC/install-arm64}"
CROSS="$BUILD/vkmt-arm64-cross.txt"

test -d "$SRC/.git" || { echo 'vkd3d-proton source is missing' >&2; exit 1; }
test -x "$TOOL/aarch64-w64-mingw32-clang++" || { echo 'LLVM-MinGW ARM64 compiler is missing' >&2; exit 1; }
mkdir -p "$BUILD"

cat >"$CROSS" <<EOF
[binaries]
c = '$TOOL/aarch64-w64-mingw32-clang'
cpp = '$TOOL/aarch64-w64-mingw32-clang++'
ar = '$TOOL/aarch64-w64-mingw32-ar'
strip = '$TOOL/aarch64-w64-mingw32-strip'
widl-mingw-tools-fallback = '$TOOL/aarch64-w64-mingw32-widl'

[properties]
needs_exe_wrapper = true

[built-in options]
c_args = ['-ffixed-x18', '-ffixed-x28']
cpp_args = ['-ffixed-x18', '-ffixed-x28']

[host_machine]
system = 'windows'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF

if test -f "$BUILD/meson-private/coredata.dat"; then
    meson setup "$BUILD" "$SRC" --cross-file "$CROSS" --reconfigure \
        --buildtype release --prefix "$STAGE" --bindir bin --libdir lib -Db_lundef=false
else
    meson setup "$BUILD" "$SRC" --cross-file "$CROSS" \
        --buildtype release --prefix "$STAGE" --bindir bin --libdir lib -Db_lundef=false
fi
meson compile -C "$BUILD" -j "${JOBS:-8}"
meson install -C "$BUILD"

for pe in "$STAGE/bin/d3d12.dll" "$STAGE/bin/d3d12core.dll"; do
    machine="$("$TOOL/llvm-readobj" --file-headers "$pe" | awk '/Machine:/ {print $2; exit}')"
    test "$machine" = IMAGE_FILE_MACHINE_ARM64 || {
        echo "Not ARM64 PE: $pe ($machine)" >&2
        exit 1
    }
done
printf 'Installed ARM64 vkd3d-proton runtime in %s\n' "$STAGE"
