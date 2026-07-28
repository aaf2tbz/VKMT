#!/bin/bash
# Build native arm64 Wine 11.12 with arm64ec PE enabled (aarch64 unix side).
# Same config as build-full plus arm64ec (xtajit64.dll links as arm64ec PE).
# Toolchain: llvm-mingw (arm64ec needs clang; gcc-mingw can't emit arm64ec).
# Requires the VKMT-rebuilt arm64ec CRT/runtime (scripts/rebuild-mingw-crt.sh arm64ec [cxx]).
set -euo pipefail
VKMT="$(cd "$(dirname "$0")/.." && pwd)"
LLVM_MINGW="${LLVM_MINGW:-$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal}"
SRC="$VKMT/wine/wine-11.12"
BLD="$VKMT/wine/build-ec"

mkdir -p "$BLD"

export PATH="$LLVM_MINGW/bin:/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:/opt/homebrew/bin:$PATH"
export PKG_CONFIG_PATH="/opt/homebrew/opt/freetype/lib/pkgconfig:/opt/homebrew/opt/fontconfig/lib/pkgconfig:/opt/homebrew/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export CPPFLAGS="-I$VKMT/third_party/MoltenVK/External/Vulkan-Headers/include"
export LDFLAGS="-L$VKMT/third_party/MoltenVK/Package/Release/MoltenVK/dynamic/dylib/macOS"

# Wine's configure probes *-gcc before *-clang for i386.  On a developer
# machine that can silently select Homebrew GCC even though the in-tree
# LLVM-MinGW toolchain is first on PATH, and the generated rules then receive
# Clang-only flags that GCC cannot compile.  Pin this guest compiler so every
# targeted i386 rebuild uses the same in-tree LLVM toolchain as the probes.
export i386_CC="$LLVM_MINGW/bin/i686-w64-mingw32-clang"
export i386_CXX="$LLVM_MINGW/bin/i686-w64-mingw32-clang++"

cd "$BLD"
if [ ! -f Makefile ] || ! grep -Fq "i386_CC = $i386_CC" Makefile; then
  # VKMT: PE TEB lives in x28 (Darwin scrubs x18); configure forces
  # -ffixed-x18 -ffixed-x28 for aarch64 and arm64ec (patched configure.ac).
  "$SRC/configure" \
    --enable-archs=aarch64,arm64ec,x86_64,i386 \
    --with-vulkan --with-freetype --with-fontconfig --with-opengl \
    --with-gstreamer --with-gnutls \
    --without-capi --without-dbus --without-gphoto \
    --without-pcap --without-sane --without-udev --without-wayland --without-x
fi
make -j8

# Wine resolves these optional host libraries with dlopen(). Keep their full
# ARM64 runtime closure beside win32u.so and remove absolute Homebrew load
# paths so the finished build tree remains relocatable.
"$VKMT/scripts/stage-wine-host-libs.sh" "$BLD"
echo "Built: $BLD/wine"
