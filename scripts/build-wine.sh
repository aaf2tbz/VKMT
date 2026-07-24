#!/bin/bash
# Build native arm64 Wine 11.12 (aarch64 unix side, arm64ec + x86_64 PE side).
# Toolchain: llvm-mingw (arm64ec needs clang; gcc-mingw can't emit arm64ec).
set -euo pipefail
VKMT="$(cd "$(dirname "$0")/.." && pwd)"
LLVM_MINGW="${LLVM_MINGW:-/Volumes/AverySSD/toolchains/llvm-mingw-20260616-ucrt-macos-universal}"
SRC="$VKMT/wine/wine-11.12"
BLD="$VKMT/wine/build"

if [ ! -d "$SRC" ]; then
  mkdir -p "$VKMT/wine"
  curl -L https://dl.winehq.org/wine/source/11.x/wine-11.12.tar.xz | tar xJ -C "$VKMT/wine"
fi
mkdir -p "$BLD"

export PATH="$LLVM_MINGW/bin:/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:/opt/homebrew/bin:$PATH"
export CPPFLAGS="-I$VKMT/third_party/MoltenVK/External/Vulkan-Headers/include"
export LDFLAGS="-L$VKMT/third_party/MoltenVK/Package/Release/MoltenVK/dynamic/dylib/macOS"

cd "$BLD"
if [ ! -f Makefile ]; then
  "$SRC/configure" --enable-archs=arm64ec,x86_64 --with-vulkan \
    --without-gstreamer --without-capi --without-dbus --without-gphoto \
    --without-pcap --without-sane --without-udev --without-wayland --without-x
fi
make -j"$(sysctl -n hw.perflevel0.physicalcpu)"
echo "Built: $BLD/wine"
