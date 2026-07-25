#!/bin/bash
# Build native arm64 Wine 11.12 with arm64ec PE enabled (aarch64 unix side).
# Same config as build-full plus arm64ec (xtajit64.dll links as arm64ec PE).
# Toolchain: llvm-mingw (arm64ec needs clang; gcc-mingw can't emit arm64ec).
# Requires the VKMT-rebuilt arm64ec CRT/runtime (scripts/rebuild-mingw-crt.sh arm64ec [cxx]).
set -euo pipefail
VKMT="$(cd "$(dirname "$0")/.." && pwd)"
LLVM_MINGW="${LLVM_MINGW:-/Volumes/AverySSD/toolchains/llvm-mingw-20260616-ucrt-macos-universal}"
SRC="$VKMT/wine/wine-11.12"
BLD="$VKMT/wine/build-ec"

mkdir -p "$BLD"

export PATH="$LLVM_MINGW/bin:/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:/opt/homebrew/bin:$PATH"
export PKG_CONFIG_PATH="/opt/homebrew/opt/freetype/lib/pkgconfig:/opt/homebrew/opt/fontconfig/lib/pkgconfig:/opt/homebrew/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export CPPFLAGS="-I$VKMT/third_party/MoltenVK/External/Vulkan-Headers/include"
export LDFLAGS="-L$VKMT/third_party/MoltenVK/Package/Release/MoltenVK/dynamic/dylib/macOS"

cd "$BLD"
if [ ! -f Makefile ]; then
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
echo "Built: $BLD/wine"
