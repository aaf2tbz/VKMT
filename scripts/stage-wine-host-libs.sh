#!/bin/bash
# Stage Wine's optional native host libraries as a relocatable ARM64 closure.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${1:-$VKMT/wine/build-ec}"
RUNTIME_DIR="$BUILD/dlls/win32u"
FREETYPE_SOURCE="${FREETYPE_SOURCE:-/opt/homebrew/opt/freetype/lib/libfreetype.6.dylib}"
LIBPNG_SOURCE="${LIBPNG_SOURCE:-/opt/homebrew/opt/libpng/lib/libpng16.16.dylib}"
MOLTENVK_SOURCE="${MOLTENVK_SOURCE:-$VKMT/third_party/MoltenVK/Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib}"

for source in "$FREETYPE_SOURCE" "$LIBPNG_SOURCE" "$MOLTENVK_SOURCE"; do
  test -f "$source" || { echo "Missing native host dependency: $source" >&2; exit 1; }
done

mkdir -p "$RUNTIME_DIR"
/usr/bin/ditto "$FREETYPE_SOURCE" "$RUNTIME_DIR/libfreetype.6.dylib"
/usr/bin/ditto "$LIBPNG_SOURCE" "$RUNTIME_DIR/libpng16.16.dylib"
/usr/bin/ditto "$MOLTENVK_SOURCE" "$RUNTIME_DIR/libMoltenVK.dylib"

for dylib in "$RUNTIME_DIR/libfreetype.6.dylib" "$RUNTIME_DIR/libpng16.16.dylib"; do
  test "$(/usr/bin/lipo -archs "$dylib")" = arm64 || {
    echo "Native host dependency is not ARM64-only: $dylib" >&2
    exit 1
  }
done

/usr/bin/install_name_tool -id '@loader_path/libfreetype.6.dylib' \
  "$RUNTIME_DIR/libfreetype.6.dylib"
/usr/bin/install_name_tool -change \
  /opt/homebrew/opt/libpng/lib/libpng16.16.dylib \
  '@loader_path/libpng16.16.dylib' \
  "$RUNTIME_DIR/libfreetype.6.dylib"
/usr/bin/install_name_tool -id '@loader_path/libpng16.16.dylib' \
  "$RUNTIME_DIR/libpng16.16.dylib"
/usr/bin/codesign --force --sign - "$RUNTIME_DIR/libfreetype.6.dylib"
/usr/bin/codesign --force --sign - "$RUNTIME_DIR/libpng16.16.dylib"

/usr/bin/otool -L "$RUNTIME_DIR/libfreetype.6.dylib" | \
  grep -Fq '@loader_path/libpng16.16.dylib' || {
    echo "FreeType does not resolve the staged libpng relatively" >&2
    exit 1
  }
if /usr/bin/otool -L "$RUNTIME_DIR/libfreetype.6.dylib" \
    "$RUNTIME_DIR/libpng16.16.dylib" | grep -Fq /opt/homebrew/; then
  echo "Staged FreeType/libpng closure still depends on Homebrew paths" >&2
  exit 1
fi
/usr/bin/codesign --verify "$RUNTIME_DIR/libfreetype.6.dylib" \
  "$RUNTIME_DIR/libpng16.16.dylib"

printf 'Staged relocatable ARM64 host libraries in %s\n' "$RUNTIME_DIR"
