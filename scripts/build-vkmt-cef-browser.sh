#!/bin/bash
# Build VKMT's user-facing x86_64 CEF browser host. This is intentionally
# separate from the diagnostic cefclient sample and owns initial navigation.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION='109.1.18+gf1c41e4+chromium-109.0.5414.120'
SDK="$VKMT/third_party/cef-$VERSION/windows64-sdk"
TOOLCHAIN="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
OUT="$VKMT/build/vkmt-cef-browser/x86_64"

test -f "$SDK/include/cef_app.h" || {
  echo "Missing CEF 109 SDK headers: $SDK" >&2
  exit 1
}
test -f "$SDK/Release/libcef.lib" || {
  echo "Missing CEF 109 import library: $SDK/Release/libcef.lib" >&2
  exit 1
}
mkdir -p "$OUT"
BUILD="$OUT/cmake"
cmake -S "$VKMT/third_party/metalsharp-cef" -B "$BUILD" -G Ninja \
  -DCEF_ROOT="$SDK" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_SYSTEM_NAME=Windows \
  -DCMAKE_C_COMPILER="$TOOLCHAIN/x86_64-w64-mingw32-clang" \
  -DCMAKE_CXX_COMPILER="$TOOLCHAIN/x86_64-w64-mingw32-clang++" \
  -DCMAKE_RC_COMPILER="$TOOLCHAIN/llvm-rc" \
  -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
cmake --build "$BUILD" --target vkmt-browser
cp -f "$BUILD/vkmt-browser.exe" "$OUT/vkmt-browser.exe"
"$TOOLCHAIN/llvm-readobj" --file-headers "$OUT/vkmt-browser.exe" | \
  grep -q 'Machine: IMAGE_FILE_MACHINE_AMD64'
echo "VKMT_CEF_BROWSER_BUILD_OK $OUT/vkmt-browser.exe"
