#!/bin/bash
# Stage Wine's pinned Gecko redistributables beside the build tree.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$VKMT/third_party/wine-gecko-2.47.4"
STAGE="$VKMT/wine/gecko"
EXTRACTOR="${MSIEXTRACT:-$(command -v msiextract || true)}"

if test -z "$EXTRACTOR"; then
  echo "msiextract is required to stage Wine Gecko" >&2
  exit 1
fi

check()
{
  expected=$1
  file=$2
  echo "$expected  $file" | shasum -a 256 -c -
}
check 26cecc47706b091908f7f814bddb074c61beb8063318e9efc5a7f789857793d6 \
  "$SOURCE/wine-gecko-2.47.4-x86.msi"
check e590b7d988a32d6aa4cf1d8aa3aa3d33766fdd4cf4c89c2dcc2095ecb28d066f \
  "$SOURCE/wine-gecko-2.47.4-x86_64.msi"

tmp="$(mktemp -d "$VKMT/build/gecko-stage.XXXXXX")"
cleanup()
{
  case "$tmp" in "$VKMT/build"/gecko-stage.*)
    /usr/bin/trash "$tmp" 2>/dev/null || true
  esac
}
trap cleanup EXIT

stage_arch()
{
  package=$1
  arch=$2
  extracted="$tmp/$arch"
  destination="$STAGE/wine-gecko-2.47.4-$arch"

  mkdir -p "$extracted"
  "$EXTRACTOR" -C "$extracted" "$SOURCE/$package" >/dev/null
  payload="$extracted/gecko/2.47.4/wine_gecko"
  test -f "$payload/xul.dll"
  test -f "$payload/VERSION"

  incoming="$tmp/wine-gecko-2.47.4-$arch"
  /usr/bin/ditto "$payload" "$incoming"
  mkdir -p "$STAGE"
  if test -e "$destination"; then
    /usr/bin/trash "$destination"
  fi
  mv "$incoming" "$destination"
}

stage_arch wine-gecko-2.47.4-x86.msi x86
stage_arch wine-gecko-2.47.4-x86_64.msi x86_64

# Keep the signed redistributables as provenance and as the install fallback.
install -m 0644 "$SOURCE/wine-gecko-2.47.4-x86.msi" "$STAGE/"
install -m 0644 "$SOURCE/wine-gecko-2.47.4-x86_64.msi" "$STAGE/"
echo WINE_GECKO_2_47_4_STAGE_OK
