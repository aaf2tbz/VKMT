#!/bin/bash
# Stage or verify the paired DXMT 0.80 ARM64EC DXGI/D3D11 provider.
# The two DLLs are one ABI unit: never allow a prefix to retain only one.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${WINEBUILDDIR:-$VKMT/wine/build-ec}"
DXMT="$BUILD/dxmt-v0.80/aarch64-windows"
D3D11_SHA256=f39bad475dca36678b2815a467f9ff2c78927c266976dabebd8c06e044fe1215
DXGI_SHA256=55ecfb520d0c2a09435fda5c3b5c62026623486e813e5d42f78093e3af79f12a

usage()
{
    echo "usage: $0 --prefix PREFIX | --verify-prefix PREFIX" >&2
    exit 2
}

test "$#" = 2 || usage
case "$1" in
    --prefix) mode=stage ;;
    --verify-prefix) mode=verify ;;
    *) usage ;;
esac
prefix=$2
system32="$prefix/drive_c/windows/system32"
receipt="$prefix/.vkmt/dxmt-arm64ec.sha256"

check()
{
    echo "$1  $2" | shasum -a 256 -c -
}

check "$D3D11_SHA256" "$DXMT/d3d11.dll"
check "$DXGI_SHA256" "$DXMT/dxgi.dll"

if test "$mode" = stage; then
    mkdir -p "$system32" "$prefix/.vkmt"
    # Install both before writing the receipt. An interrupted stage therefore
    # cannot be mistaken for an accepted provider pair.
    install -m 0644 "$DXMT/d3d11.dll" "$system32/d3d11.dll"
    install -m 0644 "$DXMT/dxgi.dll" "$system32/dxgi.dll"
    {
        echo "$D3D11_SHA256  d3d11.dll"
        echo "$DXGI_SHA256  dxgi.dll"
    } >"$receipt"
fi

check "$D3D11_SHA256" "$system32/d3d11.dll"
check "$DXGI_SHA256" "$system32/dxgi.dll"
test "$(cat "$receipt")" = "$(printf '%s\n%s' \
    "$D3D11_SHA256  d3d11.dll" "$DXGI_SHA256  dxgi.dll")"

echo VKMT_DXMT_ARM64EC_PAIR_OK
