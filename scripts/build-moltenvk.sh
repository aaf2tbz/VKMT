#!/bin/bash
# Build MoltenVK for macOS using Xcode-beta (xcode-select points at CLT on this machine).
set -euo pipefail
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Users/averyfelts/Downloads/Xcode-beta.app/Contents/Developer}"
cd "$(dirname "$0")/../third_party/MoltenVK"
./fetchDependencies --macos
make macos
echo "Built: $(ls -d Package/Release/MoltenVK/MoltenVK.xcframework 2>/dev/null || true)"
