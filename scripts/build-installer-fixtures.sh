#!/bin/bash
# Build deterministic WiX/MSI acceptance fixtures with native ARM64 tools.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$VKMT/test/installers"
OUTPUT="$VKMT/build/installer-fixtures"
TOOLCHAIN="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"

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

build_extended()
{
  arch=$1
  triple=$2
  machine=$3
  service="$OUTPUT/vkmt-msi-service-$arch.exe"
  custom="$OUTPUT/vkmt-msi-custom-$arch.dll"

  "$TOOLCHAIN/$triple-clang" -O2 "$SOURCE/vkmt-msi-service.c" \
    -o "$service" -ladvapi32
  "$TOOLCHAIN/$triple-clang" -O2 -shared "$SOURCE/vkmt-msi-custom.c" \
    -o "$custom" -lmsi
  test "$("$TOOLCHAIN/llvm-readobj" --file-headers "$service" |
    awk '/Machine:/ {print $2; exit}')" = "$machine"

  wixl --arch "$arch" \
    -D ProductCode='{D0A8B320-6D92-4CA7-A071-000000000201}' \
    -D ProductVersion=1.0.0 \
    -D ComponentGuid='{50D6083E-A47B-4D14-9669-000000000201}' \
    -D Marker="$SOURCE/vkmt-msi-marker.txt" \
    -D ServiceExe="$service" -D CustomDll="$custom" \
    -o "$OUTPUT/vkmt-msi-extended-$arch-v1.msi" \
    "$SOURCE/vkmt-msi-extended.wxs"
  wixl --arch "$arch" \
    -D ProductCode='{D0A8B320-6D92-4CA7-A071-000000000202}' \
    -D ProductVersion=2.0.0 \
    -D ComponentGuid='{50D6083E-A47B-4D14-9669-000000000202}' \
    -D Marker="$SOURCE/vkmt-msi-v2-marker.txt" \
    -D ServiceExe="$service" -D CustomDll="$custom" \
    -o "$OUTPUT/vkmt-msi-extended-$arch-v2.msi" \
    "$SOURCE/vkmt-msi-extended.wxs"
}
build_extended x86 i686-w64-mingw32 IMAGE_FILE_MACHINE_I386
build_extended x64 x86_64-w64-mingw32 IMAGE_FILE_MACHINE_AMD64

msiinfo suminfo "$OUTPUT/vkmt-msi-x86.msi" >"$OUTPUT/vkmt-msi-x86.summary"
msiinfo suminfo "$OUTPUT/vkmt-msi-x64.msi" >"$OUTPUT/vkmt-msi-x64.summary"
printf '%s\n' \
  "wixl=$(wixl --version)" \
  >"$OUTPUT/tool-versions.txt"
echo INSTALLER_FIXTURES_MSI_OK
