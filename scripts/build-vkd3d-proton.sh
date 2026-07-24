#!/bin/bash
# Cross-build vkd3d-proton Windows DLLs (d3d12.dll, d3d12core.dll, dxgi.dll bits).
# Requires: mingw-w64, meson, ninja, glslang (brew).
set -euo pipefail
export PATH="/opt/homebrew/bin:$PATH"
cd "$(dirname "$0")/../third_party/vkd3d-proton"
meson setup build-win64 --cross-file build-win64.txt --prefix "$PWD/install-win64" --wipe
ninja -C build-win64
ninja -C build-win64 install
echo "Installed to third_party/vkd3d-proton/install-win64"
