#!/bin/bash
# Extract the user's private, notarized Oracle ARM64 JRE into the VKMT tree.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="${VKMT_ORACLE_JRE_DMG:-/Users/averyfelts/Desktop/jre-8u501-macosx-aarch64.dmg}"
EXPECTED_SHA=3f488bb03113460719c4c16737c37e2ee22a85487b877b146bd33e4b4a00e7d1
PRIVATE_ROOT="$VKMT/third_party/private"
PINNED_DMG="$PRIVATE_ROOT/oracle-jre-8u501-macosx-aarch64.dmg"
STAGE="$PRIVATE_ROOT/oracle-jre-8u501-arm64"
BUILD="$VKMT/build/native-java-stage"
mountpoint=
temporary=

cleanup()
{
  status=$?
  if test -n "$mountpoint"; then
    hdiutil detach "$mountpoint" >/dev/null 2>&1 || true
  fi
  if test -n "$temporary" && test -d "$temporary"; then
    rm -rf "$temporary"
  fi
  exit "$status"
}
trap cleanup EXIT

mkdir -p "$PRIVATE_ROOT" "$BUILD"
if test ! -f "$PINNED_DMG"; then
  test -f "$SOURCE" || { echo "Missing Oracle JRE DMG: $SOURCE" >&2; exit 1; }
  printf '%s  %s\n' "$EXPECTED_SHA" "$SOURCE" | shasum -a 256 -c -
  ditto "$SOURCE" "$PINNED_DMG"
fi
printf '%s  %s\n' "$EXPECTED_SHA" "$PINNED_DMG" | shasum -a 256 -c -

if test ! -d "$STAGE/Home"; then
  temporary="$(mktemp -d "$BUILD/extract.XXXXXX")"
  hdiutil attach -readonly -nobrowse "$PINNED_DMG" >"$temporary/attach.log"
  mountpoint="$(awk -F '\t' 'NF >= 3 { mount = $NF } END { print mount }' \
    "$temporary/attach.log")"
  test -n "$mountpoint"
  installer="$mountpoint/Java 8 Update 501.app"
  package="$installer/Contents/Resources/JavaAppletPlugin.pkg"
  test -f "$package"
  codesign --verify --deep --strict "$installer"
  pkgutil --check-signature "$package" >"$temporary/package-signature.txt"
  grep -q 'Developer ID Installer: Oracle America, Inc.' \
    "$temporary/package-signature.txt"
  grep -q 'Notarization: trusted by the Apple notary service' \
    "$temporary/package-signature.txt"
  pkgutil --expand-full "$package" "$temporary/package"
  payload="$temporary/package/JavaAppletPlugin.pkg/Payload/Contents"
  test -x "$payload/Home/bin/java"
  test "$(file "$payload/Home/bin/java")" = \
    "$payload/Home/bin/java: Mach-O 64-bit executable arm64"
  ditto "$payload" "$STAGE"
  hdiutil detach "$mountpoint" >/dev/null
  mountpoint=
fi

test -x "$STAGE/Home/bin/java"
test -f "$STAGE/Home/lib/server/libjvm.dylib"
test "$(lipo -archs "$STAGE/Home/bin/java")" = arm64
test "$(lipo -archs "$STAGE/Home/lib/server/libjvm.dylib")" = arm64
codesign --verify --strict "$STAGE/Home/bin/java"
codesign --verify --strict "$STAGE/Home/lib/server/libjvm.dylib"
if otool -L "$STAGE/Home/bin/java" "$STAGE/Home/lib/server/libjvm.dylib" |
   grep -q '/opt/homebrew'; then
  echo "Oracle JRE has an unexpected Homebrew dependency" >&2
  exit 1
fi
"$STAGE/Home/bin/java" -version 2>&1 | grep -F '1.8.0_501'
"$STAGE/Home/bin/java" -server -XshowSettings:properties -version 2>&1 |
  grep -F 'java.vm.name = Java HotSpot(TM) 64-Bit Server VM'

install -m 0644 "$VKMT/runtime-manifests/oracle-jre-8u501-arm64.txt" \
  "$STAGE/PROVENANCE.txt"

echo "VKMT_NATIVE_ORACLE_JRE_8U501_STAGE_OK"
