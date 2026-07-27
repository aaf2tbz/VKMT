#!/bin/bash
# Build FEX-2607's native ARM64 Windows/WoW64 CPU provider as Wine xtajit.dll.
# This executes i386 PE code on Apple Silicon without Rosetta; Wine itself
# continues to provide the WoW64 syscall and native ARM64 Unixlib boundary.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
LLVM_MINGW="${LLVM_MINGW:-$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal}"
SRC="$VKMT/third_party/FEX-2607"
BLD="$VKMT/build/fex-wow64"
STAGE="$VKMT/wine/build-ec/dlls/xtajit/aarch64-windows"

test -d "$SRC/.git" || {
  echo "Missing $SRC; run scripts/fetch.sh first" >&2
  exit 1
}
test -x "$VKMT/wine/build-ec/wine" || {
  echo "Missing native Wine build at $VKMT/wine/build-ec; run scripts/build-ec.sh first" >&2
  exit 1
}

export PATH="$LLVM_MINGW/bin:/opt/homebrew/bin:$PATH"

# CMake stores absolute archiver/ranlib paths in per-language compiler metadata.
# If this checkout moved from an older toolchain location, retain the configured
# FEX objects but discard only that stale generated metadata before reconfigure.
if [ -d "$BLD/CMakeFiles" ] && \
   find "$BLD/CMakeFiles" -name 'CMake*Compiler.cmake' -type f -exec grep -q '/Volumes/AverySSD/toolchains/' {} \; -print -quit | grep -q .; then
  find "$BLD/CMakeFiles" -name 'CMake*Compiler.cmake' -type f -delete
fi

cmake -U 'CMAKE_*_COMPILER*' -U CMAKE_RANLIB -S "$SRC" -B "$BLD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="$SRC/Data/CMake/toolchain_mingw.cmake" \
  -DMINGW_TRIPLE=aarch64-w64-mingw32 \
  -DCMAKE_C_COMPILER="$LLVM_MINGW/bin/aarch64-w64-mingw32-clang" \
  -DCMAKE_CXX_COMPILER="$LLVM_MINGW/bin/aarch64-w64-mingw32-clang++" \
  -DCMAKE_ASM_COMPILER="$LLVM_MINGW/bin/aarch64-w64-mingw32-clang" \
  -DCMAKE_C_COMPILER_AR="$LLVM_MINGW/bin/aarch64-w64-mingw32-llvm-ar" \
  -DCMAKE_CXX_COMPILER_AR="$LLVM_MINGW/bin/aarch64-w64-mingw32-llvm-ar" \
  -DCMAKE_ASM_COMPILER_AR="$LLVM_MINGW/bin/aarch64-w64-mingw32-llvm-ar" \
  -DCMAKE_C_COMPILER_RANLIB="$LLVM_MINGW/bin/aarch64-w64-mingw32-llvm-ranlib" \
  -DCMAKE_CXX_COMPILER_RANLIB="$LLVM_MINGW/bin/aarch64-w64-mingw32-llvm-ranlib" \
  -DCMAKE_ASM_COMPILER_RANLIB="$LLVM_MINGW/bin/aarch64-w64-mingw32-llvm-ranlib" \
  -DBUILD_TESTING=OFF \
  -DENABLE_LTO=OFF \
  -DENABLE_JEMALLOC_GLIBC_ALLOC=OFF \
  -DTUNE_CPU=none \
  -DCMAKE_DISABLE_FIND_PACKAGE_fmt=TRUE \
  -DCMAKE_C_FLAGS=-ffixed-x28 \
  -DCMAKE_CXX_FLAGS=-ffixed-x28 \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DCMAKE_INSTALL_LIBDIR=lib/wine/aarch64-windows

ninja -C "$BLD" wow64fex -j8
install -d "$STAGE"
install -m 0755 "$BLD/Bin/libwow64fex.dll" "$STAGE/xtajit.dll"
python3 "$VKMT/scripts/fix-x18-tls.py" "$STAGE/xtajit.dll"
echo "Staged: $STAGE/xtajit.dll"
