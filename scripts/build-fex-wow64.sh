#!/bin/bash
# Build FEX-2607's native ARM64 Windows/WoW64 CPU provider as Wine xtajit.dll.
# This executes i386 PE code on Apple Silicon without Rosetta; Wine itself
# continues to provide the WoW64 syscall and native ARM64 Unixlib boundary.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
LLVM_MINGW="${LLVM_MINGW:-/Volumes/AverySSD/toolchains/llvm-mingw-20260616-ucrt-macos-universal}"
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

cmake -S "$SRC" -B "$BLD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_TOOLCHAIN_FILE="$SRC/Data/CMake/toolchain_mingw.cmake" \
  -DMINGW_TRIPLE=aarch64-w64-mingw32 \
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
echo "Staged: $STAGE/xtajit.dll"
