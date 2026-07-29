#!/bin/bash
# Build and stage the pinned native ARM64 innoextract fallback.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$VKMT/third_party/innoextract-1.9-g6e9e34e"
BUILD="$VKMT/build/innoextract-native-arm64"
STAGE="$VKMT/wine/build-ec/installer-runtime/innoextract"
PATCH="$VKMT/patches/innoextract-boost-system-header-only.patch"
COMMIT=6e9e34ed0876014fdb46e684103ef8c3605e382e

test "$(git -C "$SOURCE" rev-parse HEAD)" = "$COMMIT"
if git -C "$SOURCE" apply --reverse --check "$PATCH" 2>/dev/null; then
  :
else
  git -C "$SOURCE" apply "$PATCH"
fi

cmake --fresh -S "$SOURCE" -B "$BUILD" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_PREFIX_PATH=/opt/homebrew
cmake --build "$BUILD" -j"${VKMT_INNO_JOBS:-8}"

mkdir -p "$STAGE"
install -m 0755 "$BUILD/innoextract" "$STAGE/innoextract"
sources=("$BUILD/innoextract")
index=0
while test "$index" -lt "${#sources[@]}"; do
  source="${sources[$index]}"
  index=$((index + 1))
  while IFS= read -r dependency; do
    case "$dependency" in
      /opt/homebrew/*)
        found=0
        for known in "${sources[@]}"; do
          test "$known" != "$dependency" || { found=1; break; }
        done
        test "$found" = 1 || sources+=("$dependency")
        ;;
    esac
  done < <(otool -L "$source" | awk 'NR > 1 {print $1}')
done

for source in "${sources[@]:1}"; do
  test "$(/usr/bin/lipo -archs "$source")" = arm64
  install -m 0755 "$source" "$STAGE/$(basename "$source")"
done
for source in "${sources[@]}"; do
  staged="$STAGE/$(basename "$source")"
  test "$source" != "$BUILD/innoextract" ||
    staged="$STAGE/innoextract"
  while IFS= read -r dependency; do
    case "$dependency" in
      /opt/homebrew/*)
        install_name_tool -change "$dependency" \
          "@loader_path/$(basename "$dependency")" "$staged"
        ;;
    esac
  done < <(otool -L "$source" | awk 'NR > 1 {print $1}')
  case "$staged" in *.dylib)
    install_name_tool -id "@loader_path/$(basename "$staged")" "$staged"
  esac
  codesign --force --sign - "$staged"
  test "$(/usr/bin/lipo -archs "$staged")" = arm64
  ! otool -L "$staged" | grep -Eq '/(opt/homebrew|usr/local)/'
done

{
  echo "INNOEXTRACT_COMMIT=$COMMIT"
  echo "INNO_SETUP_EXECUTION_VERSION=6.5.4"
  echo "INNO_SETUP_EXTRACTION_VERSION=6.3.3"
} >"$STAGE/manifest.txt"
echo INNOEXTRACT_NATIVE_ARM64_STAGE_OK
