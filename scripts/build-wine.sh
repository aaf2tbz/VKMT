#!/bin/bash
# Build native arm64 Wine 11.12 (aarch64 unix side) for MetalSharp/VKMT.
# PE archs: arm64ec + aarch64 (ARM64X), x86_64 and i386 (run via Wine's own
# xtajit/wow64 emulation in-process — NO Rosetta anywhere).
# Toolchain: llvm-mingw (arm64ec needs clang; gcc-mingw can't emit arm64ec).
# Deps: brew install bison flex freetype fontconfig pkg-config
set -euo pipefail
VKMT="$(cd "$(dirname "$0")/.." && pwd)"
LLVM_MINGW="${LLVM_MINGW:-/Volumes/AverySSD/toolchains/llvm-mingw-20260616-ucrt-macos-universal}"
SRC="$VKMT/wine/wine-11.12"
BLD="$VKMT/wine/build-full"

if [ ! -d "$SRC" ]; then
  mkdir -p "$VKMT/wine"
  curl -L https://dl.winehq.org/wine/source/11.x/wine-11.12.tar.xz | tar xJ -C "$VKMT/wine"
fi
mkdir -p "$BLD"

export PATH="$LLVM_MINGW/bin:/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:/opt/homebrew/bin:$PATH"
export PKG_CONFIG_PATH="/opt/homebrew/opt/freetype/lib/pkgconfig:/opt/homebrew/opt/fontconfig/lib/pkgconfig:/opt/homebrew/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
export CPPFLAGS="-I$VKMT/third_party/MoltenVK/External/Vulkan-Headers/include"
export LDFLAGS="-L$VKMT/third_party/MoltenVK/Package/Release/MoltenVK/dynamic/dylib/macOS"

cd "$BLD"
if [ ! -f Makefile ]; then
  # VKMT: PE TEB lives in x28 (Darwin scrubs x18); reserve x28 in all aarch64 PE code.
  aarch64_CFLAGS="-g -O2 -ffixed-x18 -ffixed-x28" \
  "$SRC/configure" \
    --enable-archs=arm64ec,aarch64,x86_64,i386 \
    --with-vulkan --with-freetype --with-fontconfig --with-opengl \
    --with-gstreamer --with-gnutls \
    --without-capi --without-dbus --without-gphoto \
    --without-pcap --without-sane --without-udev --without-wayland --without-x
fi
make -j"$(sysctl -n hw.perflevel0.physicalcpu)"
echo "Built: $BLD/wine"
