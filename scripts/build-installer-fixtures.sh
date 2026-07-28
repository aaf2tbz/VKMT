#!/bin/bash
# Build deterministic WiX/MSI acceptance fixtures with native ARM64 tools.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$VKMT/test/installers"
OUTPUT="$VKMT/build/installer-fixtures"

for tool in wixl; do
  command -v "$tool" >/dev/null 2>&1 || {
    echo "Missing installer-fixture tool: $tool" >&2
    exit 1
  }
  test "$(/usr/bin/lipo -archs "$(command -v "$tool")")" = arm64 || {
    echo "Installer-fixture tool is not native ARM64: $tool" >&2
    exit 1
  }
done

mkdir -p "$OUTPUT"
wixl --arch x86 -o "$OUTPUT/vkmt-msi-x86.msi" "$SOURCE/vkmt-msi.wxs"
wixl --arch x64 -o "$OUTPUT/vkmt-msi-x64.msi" "$SOURCE/vkmt-msi.wxs"

msiinfo suminfo "$OUTPUT/vkmt-msi-x86.msi" >"$OUTPUT/vkmt-msi-x86.summary"
msiinfo suminfo "$OUTPUT/vkmt-msi-x64.msi" >"$OUTPUT/vkmt-msi-x64.summary"
printf '%s\n' \
  "wixl=$(wixl --version)" \
  >"$OUTPUT/tool-versions.txt"
echo INSTALLER_FIXTURES_MSI_OK
