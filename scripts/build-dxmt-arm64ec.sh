#!/bin/bash
# Build DXMT v0.80 for x64-on-ARM64 Wine: ARM64EC PE DLLs + arm64 Unix driver.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$VKMT/third_party/dxmt-src-v0.80"
BUILD="$SRC/build-vkmt-arm64ec"
STAGE="$VKMT/wine/build-ec/dxmt-v0.80"
WINE_BUILD="$VKMT/wine/build-ec"
LLVM_MINGW="${LLVM_MINGW:-/Volumes/AverySSD/toolchains/llvm-mingw-20260616-ucrt-macos-universal}"
LLVM15="${LLVM15:-/opt/homebrew/opt/llvm@15}"

test -d "$SRC/.git" || { echo "Run scripts/fetch.sh first" >&2; exit 1; }
test -x "$WINE_BUILD/tools/winebuild/winebuild" || { echo "Build Wine first: scripts/build-ec.sh" >&2; exit 1; }
test -x "$LLVM_MINGW/bin/arm64ec-w64-mingw32-gcc" || { echo "ARM64EC llvm-mingw is required" >&2; exit 1; }
test -x "$LLVM15/bin/llvm-config" || { echo "LLVM 15 is required (brew install llvm@15)" >&2; exit 1; }

# Prefer a full Xcode bundle when the global selection is only Command Line
# Tools.  A caller can always set DEVELOPER_DIR explicitly.
if [ -z "${DEVELOPER_DIR:-}" ]; then
  for candidate in /Applications/Xcode.app /Applications/Xcode-beta.app "$HOME/Downloads/Xcode-beta.app"; do
    if [ -d "$candidate/Contents/Developer" ]; then
      export DEVELOPER_DIR="$candidate/Contents/Developer"
      break
    fi
  done
fi

# Xcode 27 ships Metal as a downloadable component.  xcrun gives a useful
# diagnostic and the exact xcodebuild command when it has not been installed.
export PATH="$LLVM_MINGW/bin:/opt/homebrew/bin:$PATH"
xcrun --find metal >/dev/null
xcrun --find metallib >/dev/null

meson setup "$BUILD" "$SRC" --cross-file "$SRC/build-arm64ec.txt" --buildtype release \
  --prefix "$STAGE" -Dnative_llvm_path="$LLVM15" -Dwine_build_path="$WINE_BUILD" \
  -Denable_tests=false -Dc_args=-ffixed-x28 -Dcpp_args=-ffixed-x28 --wipe
meson compile -C "$BUILD" -j "${JOBS:-8}"
meson install -C "$BUILD"

# A Wine installation already has these beside winemetal.so.  Copy them into
# the build-tree stage too, so WINEDLLPATH can load-test the exact shipped pair.
cp "$WINE_BUILD/dlls/winemac.drv/winemac.so" "$STAGE/aarch64-unix/winemac.so"
cp "$WINE_BUILD/dlls/ntdll/ntdll.so" "$STAGE/aarch64-unix/ntdll.so"

echo "Installed DXMT ARM64EC/arm64 runtime to $STAGE"
