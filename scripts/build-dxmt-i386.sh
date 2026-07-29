#!/bin/bash
# Build DXMT v0.80 i386 PE modules. The paired Unix Winemetal bridge remains
# the existing native ARM64 aarch64-unix/winemetal.so; there is no i386 Mach-O.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$VKMT/third_party/dxmt-src-v0.80"
BUILD="$SRC/build-vkmt-i386"
STAGE="$VKMT/wine/build-ec/dxmt-v0.80"
WINE_BUILD="$VKMT/wine/build-ec"
LLVM15="${LLVM15:-/opt/homebrew/opt/llvm@15}"

test -d "$SRC/.git"
test -x "$WINE_BUILD/tools/winebuild/winebuild"
test -x /opt/homebrew/bin/i686-w64-mingw32-gcc
test -x "$LLVM15/bin/llvm-config"
test -f "$STAGE/aarch64-unix/winemetal.so" || {
  echo 'Build/stage ARM64 DXMT first' >&2; exit 1;
}

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "$HOME/Downloads/Xcode-beta.app/Contents/Developer" ]; then
  export DEVELOPER_DIR="$HOME/Downloads/Xcode-beta.app/Contents/Developer"
fi
xcrun --find metal >/dev/null

meson setup "$BUILD" "$SRC" --cross-file "$SRC/build-win32.txt" --buildtype release \
  --prefix "$STAGE" -Dnative_llvm_path="$LLVM15" -Dwine_build_path="$WINE_BUILD" \
  -Denable_tests=false
meson compile -C "$BUILD" -j "${JOBS:-8}"
meson install -C "$BUILD"

test -f "$STAGE/i386-windows/winemetal.dll"
echo "Installed DXMT i386 PE modules to $STAGE/i386-windows; paired Unix bridge is aarch64-unix/winemetal.so"
