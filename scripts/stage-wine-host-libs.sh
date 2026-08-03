#!/bin/bash
# Stage Wine's optional native host libraries as a relocatable ARM64 closure.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${1:-$VKMT/wine/build-ec}"
RUNTIME_DIR="$BUILD/dlls/win32u"
FREETYPE_SOURCE="${FREETYPE_SOURCE:-/opt/homebrew/opt/freetype/lib/libfreetype.6.dylib}"
LIBPNG_SOURCE="${LIBPNG_SOURCE:-/opt/homebrew/opt/libpng/lib/libpng16.16.dylib}"
MOLTENVK_SOURCE="${MOLTENVK_SOURCE:-$VKMT/third_party/MoltenVK/Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib}"
EGL_SOURCE="${EGL_SOURCE:-/opt/homebrew/opt/mesa/lib/libEGL.1.dylib}"

for source in "$FREETYPE_SOURCE" "$LIBPNG_SOURCE" "$MOLTENVK_SOURCE" \
              "$EGL_SOURCE"; do
  test -f "$source" || { echo "Missing native host dependency: $source" >&2; exit 1; }
done

mkdir -p "$RUNTIME_DIR"
/usr/bin/ditto "$FREETYPE_SOURCE" "$RUNTIME_DIR/libfreetype.6.dylib"
/usr/bin/ditto "$LIBPNG_SOURCE" "$RUNTIME_DIR/libpng16.16.dylib"
/usr/bin/ditto "$MOLTENVK_SOURCE" "$RUNTIME_DIR/libMoltenVK.dylib"

# win32u dlopens libEGL rather than linking it.  The normal runtime environment
# intentionally excludes Homebrew, so stage Mesa's complete ARM64 dependency
# closure beside win32u and rewrite it to @loader_path-relative references.
mesa_sources=("$EGL_SOURCE")
index=0
while test "$index" -lt "${#mesa_sources[@]}"; do
  source="${mesa_sources[$index]}"
  index=$((index + 1))
  while IFS= read -r dependency; do
    case "$dependency" in /opt/homebrew/*) ;; *) continue ;; esac
    test -f "$dependency" || {
      echo "Missing Mesa host dependency: $dependency" >&2
      exit 1
    }
    known=0
    for candidate in "${mesa_sources[@]}"; do
      test "$candidate" = "$dependency" && { known=1; break; }
    done
    test "$known" = 1 || mesa_sources+=("$dependency")
  done < <(/usr/bin/otool -L "$source" | awk 'NR > 1 {print $1}')
done

for source in "${mesa_sources[@]}"; do
  destination="$RUNTIME_DIR/$(basename "$source")"
  if test -e "$destination"; then
    # The existing staged file has been rewritten and signed below, so it
    # cannot be byte-compared to its original source on later invocations.
    rm -f "$destination"
  fi
  /usr/bin/ditto "$source" "$destination"
done

for source in "${mesa_sources[@]}"; do
  dylib="$RUNTIME_DIR/$(basename "$source")"
  test "$(/usr/bin/lipo -archs "$dylib")" = arm64 || {
    echo "Mesa host dependency is not ARM64-only: $dylib" >&2
    exit 1
  }
  /usr/bin/install_name_tool -id "@loader_path/$(basename "$dylib")" "$dylib"
  while IFS= read -r dependency; do
    case "$dependency" in
      /opt/homebrew/*)
        /usr/bin/install_name_tool -change "$dependency" \
          "@loader_path/$(basename "$dependency")" "$dylib"
        ;;
    esac
  done < <(/usr/bin/otool -L "$dylib" | awk 'NR > 1 {print $1}')
  while IFS= read -r rpath; do
    case "$rpath" in
      /opt/homebrew/*) /usr/bin/install_name_tool -delete_rpath "$rpath" "$dylib" ;;
    esac
  done < <(/usr/bin/otool -l "$dylib" | awk '
    $1 == "cmd" && $2 == "LC_RPATH" { want = 1; next }
    want && $1 == "path" { print $2; want = 0 }
  ')
  /usr/bin/codesign --force --sign - "$dylib"
done

if /usr/bin/otool -L "$RUNTIME_DIR"/libEGL.1.dylib \
    "$RUNTIME_DIR"/libgallium-*.dylib 2>/dev/null | grep -Fq /opt/homebrew/; then
  echo "Staged Mesa/EGL closure still depends on Homebrew paths" >&2
  exit 1
fi

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
