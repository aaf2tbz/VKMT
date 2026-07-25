#!/bin/sh
# VKMT: rebuild mingw-w64 CRT (libmingwex, libmingw32, crt objects) and
# winpthreads with -ffixed-x18 -ffixed-x28, then install them into the
# llvm-mingw toolchain.
#
# Why: VKMT PE binaries keep the TEB in x28 (Darwin scrubs x18 on every
# kernel->user crossing). The stock llvm-mingw CRT objects are built for
# the standard Windows aarch64 ABI, where x28 is an ordinary callee-saved
# scratch register. Any PE code that calls into CRT routines (mingw
# printf family, gdtoa, winpthreads, ...) clobbers x28 and the next TEB
# access crashes. Rebuilding the CRT with both registers fixed makes the
# toolchain safe for every VKMT PE link. arm64ec is an ARM64-compatible
# ABI and needs the same treatment.
#
# Usage:
#   rebuild-mingw-crt.sh [target]        CRT + winpthreads (default target: aarch64)
#   rebuild-mingw-crt.sh [target] cxx    also libunwind/libc++abi/libc++
#   rebuild-mingw-crt.sh cxx             same, for aarch64 (backwards compatible)
# target is aarch64 or arm64ec.
#
# Stock archives are preserved in <toolchain>/<triple>-w64-mingw32/lib-backup-stock.
set -e

MODE=
TARGET=aarch64
for a in "$@"; do
    case "$a" in
        cxx) MODE=cxx ;;
        aarch64|arm64ec) TARGET=$a ;;
        *) echo "unknown argument: $a" >&2; exit 1 ;;
    esac
done
TRIPLE=$TARGET-w64-mingw32

TC=${LLVM_MINGW:-/Volumes/AverySSD/toolchains/llvm-mingw-20260616-ucrt-macos-universal}
SRC=$(cd "$(dirname "$0")/../third_party" && pwd)
TCLIB=$TC/$TRIPLE/lib
FLAGS='-O2 -ffixed-x18 -ffixed-x28'
export PATH=$TC/bin:$PATH

if [ ! -d "$SRC/mingw-w64" ]; then
    git clone --depth 1 https://github.com/mingw-w64/mingw-w64.git "$SRC/mingw-w64"
elif [ "$TARGET" = arm64ec ] && ! grep -q 'host_cpu = arm64ec' "$SRC/mingw-w64/mingw-w64-crt/configure"; then
    # arm64ec CRT support needs a recent mingw-w64; refresh the shallow clone.
    (cd "$SRC/mingw-w64" && git fetch --depth 1 origin master && git checkout FETCH_HEAD)
fi

# --- CRT ---
# arm64ec uses the libarm64 build with -target arm64ec-windows-gnu applied
# automatically by mingw-w64's Makefile (host_cpu = arm64ec => ARM64EC_TRUE).
mkdir -p "$SRC/build-mingw-crt-$TARGET" && cd "$SRC/build-mingw-crt-$TARGET"
[ -f Makefile ] || "$SRC/mingw-w64/mingw-w64-crt/configure" \
    --host=$TRIPLE --prefix="$PWD/stage" --with-sysroot="$TC/$TRIPLE" \
    --disable-lib32 --disable-lib64 --disable-libarm32 --enable-libarm64 \
    CC=$TRIPLE-clang CFLAGS="$FLAGS"
make -j8
make install

# --- winpthreads ---
mkdir -p "$SRC/build-winpthread-$TARGET" && cd "$SRC/build-winpthread-$TARGET"
[ -f Makefile ] || "$SRC/mingw-w64/mingw-w64-libraries/winpthreads/configure" \
    --host=$TRIPLE --prefix="$PWD/stage" --with-sysroot="$TC/$TRIPLE" \
    CC=$TRIPLE-clang CFLAGS="$FLAGS"
make -j8
make install

# --- install into toolchain (back up stock files once) ---
BK=$TC/$TRIPLE/lib-backup-stock
mkdir -p "$BK"
for f in "$SRC/build-mingw-crt-$TARGET/stage/lib/"*; do
    b=$(basename "$f")
    if [ -f "$TCLIB/$b" ]; then
        [ -f "$BK/$b" ] || cp "$TCLIB/$b" "$BK/$b"
        cp "$f" "$TCLIB/$b"
    fi
done
for b in libwinpthread.a libwinpthread.dll.a libpthread.a libpthread.dll.a libwinpthread.la; do
    [ -f "$BK/$b" ] || cp "$TCLIB/$b" "$BK/$b" 2>/dev/null || true
    cp "$SRC/build-winpthread-$TARGET/stage/lib/$b" "$TCLIB/$b"
done

echo "VKMT CRT installed into $TCLIB (stock copies in $BK)"
echo "NOTE: any PE binary linked against the stock CRT must be RELINKED (not recompiled)."
echo "NOTE: run scripts/fix-x18-tls.py on every freshly linked PE binary."

# --- C++ runtime (libunwind, libc++abi, libc++; needed by DXVK) ---
# Built from llvm-project at the exact commit the toolchain's clang was
# built from (see `<triple>-clang++ --version`).
if [ "$MODE" = "cxx" ]; then
  LLVMSHA=${LLVM_SHA:-ca7933e47d3a3451d81e72ac174dcb5aa28b59d1}
  if [ ! -d "$SRC/llvm-project" ]; then
    git clone --filter=blob:none --no-checkout --depth 1 https://github.com/llvm/llvm-project.git "$SRC/llvm-project"
  fi
  cd "$SRC/llvm-project"
  git sparse-checkout init --cone || true
  git sparse-checkout set cmake llvm/cmake llvm/utils/llvm-lit libcxx libcxxabi libunwind runtimes \
      libc/shared libc/src/__support libc/hdr libc/include/llvm-libc-macros libc/include/llvm-libc-types
  git fetch --depth 1 origin "$LLVMSHA" || true
  git checkout "$LLVMSHA"

  mkdir -p "$SRC/build-cxxrt-$TARGET" && cd "$SRC/build-cxxrt-$TARGET"
  [ -f build.ninja ] || cmake -G Ninja -S "$SRC/llvm-project/runtimes" -B . \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=$TC/bin/$TRIPLE-clang \
    -DCMAKE_CXX_COMPILER=$TC/bin/$TRIPLE-clang++ \
    -DCMAKE_SYSTEM_NAME=Windows \
    -DCMAKE_AR=$TC/bin/$TRIPLE-ar \
    -DCMAKE_RANLIB=$TC/bin/$TRIPLE-ranlib \
    -DCMAKE_C_FLAGS="$FLAGS" \
    -DCMAKE_CXX_FLAGS="$FLAGS -I$SRC/llvm-project/libc" \
    -DLLVM_ENABLE_RUNTIMES='libunwind;libcxxabi;libcxx' \
    -DLIBUNWIND_USE_COMPILER_RT=ON -DLIBUNWIND_ENABLE_SHARED=ON -DLIBUNWIND_ENABLE_STATIC=ON \
    -DLIBCXXABI_USE_COMPILER_RT=ON -DLIBCXXABI_USE_LLVM_UNWINDER=ON -DLIBCXXABI_ENABLE_SHARED=OFF \
    -DLIBCXXABI_ENABLE_STATIC=ON -DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON \
    -DLIBCXX_USE_COMPILER_RT=ON -DLIBCXX_ENABLE_SHARED=ON -DLIBCXX_ENABLE_STATIC=ON \
    -DLIBCXX_HAS_WIN32_THREAD_API=ON -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON -DLIBCXX_INCLUDE_BENCHMARKS=OFF \
    -DCMAKE_INSTALL_PREFIX=$PWD/stage
  ninja
  ninja install

  for f in libc++.a libc++.dll.a libc++abi.a libc++experimental.a libunwind.a libunwind.dll.a libc++.modules.json; do
    [ -f "$BK/$f" ] || cp "$TCLIB/$f" "$BK/$f" 2>/dev/null || true
    cp "stage/lib/$f" "$TCLIB/$f" || true
  done
  for f in libc++.dll libunwind.dll; do
    [ -f "$BK/$f" ] || cp "$TC/$TRIPLE/bin/$f" "$BK/$f"
    cp "stage/bin/$f" "$TC/$TRIPLE/bin/$f"
  done
  [ -d "$BK/include-c++" ] || cp -R "$TC/$TRIPLE/include/c++" "$BK/include-c++"
  rm -rf "$TC/$TRIPLE/include/c++"
  cp -R stage/include/c++ "$TC/$TRIPLE/include/c++"
  for f in __libunwind_config.h libunwind.h unwind.h unwind_arm64.h unwind_itanium.h; do
    [ -f "stage/include/$f" ] && cp "stage/include/$f" "$TC/$TRIPLE/include/$f"
  done
  echo "VKMT C++ runtime installed into $TC"
fi
