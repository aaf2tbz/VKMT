#!/bin/bash
# Targeted Phase 5 i386 vkd3d-proton build using the in-tree LLVM-MinGW.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$VKMT/third_party/vkd3d-proton"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
BUILD="$SRC/build-vkmt-i386-clang"
STAGE="$SRC/install-win32"
CROSS="$BUILD/vkmt-i386-cross.txt"

test -d "$SRC/.git" || { echo 'vkd3d-proton source is missing' >&2; exit 1; }
test -x "$TOOL/i686-w64-mingw32-clang++" || { echo 'In-tree LLVM-MinGW is missing' >&2; exit 1; }
mkdir -p "$BUILD"

cat >"$CROSS" <<EOF
[binaries]
c = '$TOOL/i686-w64-mingw32-clang'
cpp = '$TOOL/i686-w64-mingw32-clang++'
ar = '$TOOL/i686-w64-mingw32-ar'
strip = '$TOOL/i686-w64-mingw32-strip'
widl-mingw-tools-fallback = '$TOOL/i686-w64-mingw32-widl'

[properties]
needs_exe_wrapper = true

[host_machine]
system = 'windows'
cpu_family = 'x86'
cpu = 'i686'
endian = 'little'
EOF

if test -f "$BUILD/meson-private/coredata.dat"; then
  meson setup "$BUILD" "$SRC" --cross-file "$CROSS" --reconfigure \
    --buildtype release --prefix "$STAGE" --bindir bin --libdir lib
else
  meson setup "$BUILD" "$SRC" --cross-file "$CROSS" \
    --buildtype release --prefix "$STAGE" --bindir bin --libdir lib
fi
meson compile -C "$BUILD" -j "${JOBS:-8}"
meson install -C "$BUILD"

for pe in "$STAGE/bin/d3d12.dll" "$STAGE/bin/d3d12core.dll"; do
  machine="$("$TOOL/llvm-readobj" --file-headers "$pe" | awk '/Machine:/ {print $2; exit}')"
  test "$machine" = IMAGE_FILE_MACHINE_I386 || { echo "Not i386 PE: $pe ($machine)" >&2; exit 1; }
done
printf 'Installed targeted i386 vkd3d-proton runtime in %s\n' "$STAGE"
