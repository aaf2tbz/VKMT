#!/bin/bash
# Integrate the paired DXMT ARM64EC PE builtins into an existing Wine build
# without rebuilding Wine.  This replaces only generated build artifacts and
# retains byte-for-byte stock backups so the operation is reversible.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
STAGE="$BUILD/dxmt-v0.80"
BACKUP="$STAGE/stock-wine-builtins"

usage()
{
    echo "usage: $0 [--restore]" >&2
    exit 2
}

restore=0
case "${1:-}" in
    '') ;;
    --restore) restore=1 ;;
    *) usage ;;
esac

pe_modules=(dxgi d3d11)

if (( restore )); then
    test -f "$BACKUP/manifest.sha256" || {
        echo "No DXMT integration backup at $BACKUP" >&2
        exit 1
    }
    (cd "$BACKUP" && shasum -a 256 -c manifest.sha256)
    for module in "${pe_modules[@]}"; do
        target="$BUILD/dlls/$module/aarch64-windows/$module.dll"
        rm -f "$target"
        cp -p "$BACKUP/$module.dll" "$target"
    done
    rm -rf "$BUILD/dlls/winemetal"
    echo "Restored stock Wine DXGI/D3D11 build artifacts."
    exit 0
fi

for module in "${pe_modules[@]}" winemetal; do
    test -f "$STAGE/aarch64-windows/$module.dll" || {
        echo "Missing DXMT ARM64EC PE: $STAGE/aarch64-windows/$module.dll" >&2
        exit 1
    }
done
test -f "$STAGE/aarch64-unix/winemetal.so"
test -f "$STAGE/aarch64-unix/libunwind.1.dylib"

mkdir -p "$BACKUP"
if test ! -f "$BACKUP/manifest.sha256"; then
    for module in "${pe_modules[@]}"; do
        source="$BUILD/dlls/$module/aarch64-windows/$module.dll"
        test -f "$source" || { echo "Missing stock Wine PE: $source" >&2; exit 1; }
        cp -p "$source" "$BACKUP/$module.dll"
    done
    (cd "$BACKUP" && shasum -a 256 dxgi.dll d3d11.dll > manifest.sha256)
fi
(cd "$BACKUP" && shasum -a 256 -c manifest.sha256)

for module in "${pe_modules[@]}"; do
    target="$BUILD/dlls/$module/aarch64-windows/$module.dll"
    rm -f "$target"
    ln -s "$STAGE/aarch64-windows/$module.dll" "$target"
done

# Wine's build-tree loader derives the Unix library name from the selected PE
# path.  Keep the PE and its native bridge together under that exact path.
# The build-tree loader resolves the PE from aarch64-windows, then replaces
# its extension on the architecture-neutral build path for the Unix library.
host_dir="$BUILD/dlls/winemetal"
pe_dir="$host_dir/aarch64-windows"
mkdir -p "$pe_dir"
for name in winemetal.so libunwind.1.dylib; do
    rm -f "$host_dir/$name"
    ln -s "$STAGE/aarch64-unix/$name" "$host_dir/$name"
done
rm -f "$pe_dir/winemetal.dll"
ln -s "$STAGE/aarch64-windows/winemetal.dll" "$pe_dir/winemetal.dll"

for module in "${pe_modules[@]}" winemetal; do
    target="$BUILD/dlls/$module/aarch64-windows/$module.dll"
    test "$(readlink "$target")" = "$STAGE/aarch64-windows/$module.dll"
done
file "$host_dir/winemetal.so" | grep -q 'Mach-O.*arm64'
echo "Integrated paired DXMT ARM64EC builtins into $BUILD (stock Wine backups: $BACKUP)."
