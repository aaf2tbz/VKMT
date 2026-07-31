#!/bin/bash
# Build a fresh Phase 6 all-architecture prefix and make the accepted no-TSO
# providers authoritative in both Wine's bootstrap path and the prefix.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
PREFIX="$VKMT/prefixes/steam-no-tso-phase6"
XTAJIT64="$VKMT/build/no-tso-phase2/providers/xtajit64-no-tso-final-v15.dll"
XTAJIT="$VKMT/build/no-tso-phase2/providers/xtajit-no-tso-final-v15.dll"
XTAJIT64_SHA=a0a586eb6687dd45bdb4818e44c64294f4cfed89dc5b5bafd806c3d402100513
XTAJIT_SHA=67192836cb4eb15cb51ef5487a4ec30a3fa210bfac370e3193ede3760a4e4273

test ! -e "$PREFIX" || {
    echo "Refusing to reuse existing Phase 6 prefix: $PREFIX" >&2
    exit 1
}
test -f "$XTAJIT64"
test -f "$XTAJIT"

export VKMT_XTAJIT64_SOURCE="$XTAJIT64"
export VKMT_XTAJIT_SOURCE="$XTAJIT"
export VKMT_XTAJIT64_SHA256="$XTAJIT64_SHA"
export VKMT_XTAJIT_SHA256="$XTAJIT_SHA"
export FEX_TSOENABLED=0
export FEX_VECTORTSOENABLED=0
export FEX_MEMCPYSETTSOENABLED=0
export VKMT_STEAM_BOOTSTRAP_WAKE_RECOVERY=0

mkdir -p "$PREFIX/drive_c/windows/system32" "$PREFIX/drive_c/windows/syswow64"
install -m 0644 "$BUILD/dlls/wow64/aarch64-windows/wow64.dll" \
    "$PREFIX/drive_c/windows/system32/wow64.dll"
install -m 0644 "$BUILD/dlls/wow64win/aarch64-windows/wow64win.dll" \
    "$PREFIX/drive_c/windows/system32/wow64win.dll"
while IFS= read -r dll; do
    install -m 0644 "$dll" "$PREFIX/drive_c/windows/syswow64/$(basename "$dll")"
done < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)

# Candidate prefix staging intentionally does not alter WINEBUILDDIR. Phase 6
# needs the same accepted providers at bootstrap, so promote these exact,
# already accepted hashes explicitly.
VKMT_PROVIDER_STAGE_BUILD=1 VKMT_PROVIDER_PROMOTE=1 \
    "$VKMT/scripts/stage-runtime-providers.sh" --prefix "$PREFIX"
"$VKMT/scripts/stage-dxmt-runtime.sh" --prefix "$PREFIX"

env WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
    WINE_NO_EXPLORER=1 WINEDEBUG=-all WINEDEBUGGER=none \
    "$BUILD/wine" "$BUILD/programs/wineboot/aarch64-windows/wineboot.exe" --init \
    >"$VKMT/build/no-tso-phase6/wineboot-clean-current.log" 2>&1

# wineboot and later helper staging must not silently restore older canonical
# provider bytes. Reassert and verify both locations after initialization.
VKMT_PROVIDER_STAGE_BUILD=1 VKMT_PROVIDER_PROMOTE=1 \
    "$VKMT/scripts/stage-runtime-providers.sh" --prefix "$PREFIX"
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$PREFIX"
"$VKMT/scripts/stage-dxmt-runtime.sh" --prefix "$PREFIX"
"$VKMT/scripts/stage-dxmt-runtime.sh" --verify-prefix "$PREFIX"
test -s "$PREFIX/.vkmt/gstreamer-runtime.sha256"
echo "$XTAJIT64_SHA  $BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll" | shasum -a 256 -c -
echo "$XTAJIT_SHA  $BUILD/dlls/xtajit/aarch64-windows/xtajit.dll" | shasum -a 256 -c -

echo NO_TSO_PHASE6_PREFIX_READY
