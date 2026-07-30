#!/bin/bash
# Build FEX-2607's native ARM64 Windows/WoW64 CPU provider as Wine xtajit.dll.
# This executes i386 PE code on Apple Silicon without Rosetta; Wine itself
# continues to provide the WoW64 syscall and native ARM64 Unixlib boundary.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
LLVM_MINGW="${LLVM_MINGW:-$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal}"
SRC="${VKMT_FEX_SOURCE:-$VKMT/third_party/FEX-2607}"
BLD="${VKMT_FEX_WOW64_BUILD:-$VKMT/build/fex-wow64-java}"
OUTPUT="${VKMT_FEX_WOW64_OUTPUT:-$BLD/provider/xtajit.dll}"
CANONICAL="$VKMT/wine/build-ec/dlls/xtajit/aarch64-windows/xtajit.dll"

test -f "$SRC/CMakeLists.txt" || {
  echo "Missing FEX source tree at $SRC; run scripts/fetch.sh first or set VKMT_FEX_SOURCE" >&2
  exit 1
}
test -x "$VKMT/wine/build-ec/wine" || {
  echo "Missing native Wine build at $VKMT/wine/build-ec; run scripts/build-ec.sh first" >&2
  exit 1
}

case "$OUTPUT" in
  "$CANONICAL"|"$VKMT/wine/build-ec/"*)
    echo "Refusing to overwrite the canonical Wine/provider tree: $OUTPUT" >&2
    echo "Build candidates under $VKMT/build and promote them only after the full gate." >&2
    exit 1
    ;;
esac

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
  -DENABLE_VIXL_DISASSEMBLER=FALSE \
  -DENABLE_LTO=OFF \
  -DENABLE_JEMALLOC_GLIBC_ALLOC=OFF \
  -DTUNE_CPU=none \
  -DCMAKE_DISABLE_FIND_PACKAGE_fmt=TRUE \
  -DCMAKE_C_FLAGS=-ffixed-x28 \
  -DCMAKE_CXX_FLAGS=-ffixed-x28 \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DCMAKE_INSTALL_LIBDIR=lib/wine/aarch64-windows

ninja -C "$BLD" wow64fex -j8
install -d "$(dirname "$OUTPUT")"
install -m 0755 "$BLD/Bin/libwow64fex.dll" "$OUTPUT"
python3 "$VKMT/scripts/fix-x18-tls.py" "$OUTPUT"
shasum -a 256 "$OUTPUT" >"$OUTPUT.sha256"
echo "Candidate: $OUTPUT"
echo "Select it with VKMT_XTAJIT_SOURCE=$OUTPUT and VKMT_XTAJIT_SHA256=$(awk '{print $1}' "$OUTPUT.sha256")"
