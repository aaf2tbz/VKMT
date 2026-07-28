#!/bin/bash
# Target-build the native ARM64 MetalSharp OpenGL sidecar and stage it beside winemac.so.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$VKMT/third_party/MetalSharp"
BUILD="$VKMT/build/metalsharp-opengl"
STAGE="$VKMT/wine/build-ec/dlls/winemac.drv/metalsharp-opengl.dylib"
SPIRV_CROSS_REV=bccaa94db814af33d8ef05c153e7c34d8bd4d685
GLSLANG_REV=46ef757e048e760b46601e6e77ae0cb72c97bd2f

test "$(git -C "$SOURCE/vendor/SPIRV-Cross" rev-parse HEAD)" = "$SPIRV_CROSS_REV" || {
  echo "Unexpected SPIRV-Cross revision" >&2
  exit 1
}
test "$(git -C "$SOURCE/vendor/glslang" rev-parse HEAD)" = "$GLSLANG_REV" || {
  echo "Unexpected glslang revision" >&2
  exit 1
}

if test ! -f "$BUILD/build.ninja"; then
  cmake -S "$SOURCE" -B "$BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DBUILD_TESTING=OFF \
    -DMETALSHARP_HOST_ARCH=arm64 \
    -DMETALSHARP_WINE_ARCH=arm64
fi
cmake --build "$BUILD" --target metalsharp_opengl32 -j "${VKMT_BUILD_JOBS:-8}"

test "$(/usr/bin/lipo -archs "$BUILD/opengl32.dylib")" = arm64
install -m 0644 "$BUILD/opengl32.dylib" "$STAGE"
codesign --force --sign - "$STAGE"
test "$(/usr/bin/lipo -archs "$STAGE")" = arm64
echo "Staged native ARM64 MetalSharp OpenGL sidecar: $STAGE"
