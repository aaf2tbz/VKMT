#!/bin/bash
# Build MoltenVK for macOS using Xcode-beta (xcode-select points at CLT on this machine).
set -euo pipefail
VKMT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_DEST="${VKMT_MOLTENVK_RUNTIME_DEST:-$VKMT/wine/build-ec/dlls/win32u/libMoltenVK.dylib}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Users/averyfelts/Downloads/Xcode-beta.app/Contents/Developer}"
cd "$(dirname "$0")/../third_party/MoltenVK"
./fetchDependencies --macos
make macos
source="$(pwd)/Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib"
test -f "$source"
if test -d "$(dirname "$RUNTIME_DEST")"; then
    install -m 0755 "$source" "$RUNTIME_DEST"
    test "$(/usr/bin/lipo -archs "$RUNTIME_DEST")" = "x86_64 arm64"
    echo "Promoted runtime: $RUNTIME_DEST"
else
    echo "Runtime destination does not exist; built package only: $RUNTIME_DEST" >&2
fi
echo "Built: $(ls -d Package/Release/MoltenVK/MoltenVK.xcframework 2>/dev/null || true)"
