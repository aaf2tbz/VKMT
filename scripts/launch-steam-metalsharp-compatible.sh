#!/bin/zsh
set -euo pipefail

VKMT_ROOT=${VKMT_ROOT:-/Volumes/AverySSD/VKMT}
METALSHARP_ROOT=${METALSHARP_ROOT:-/Volumes/AverySSD/metalsharp}
BUILD=${VKMT_WINE_BUILD:-$VKMT_ROOT/wine/build-ec}
PREFIX=${WINEPREFIX:-$VKMT_ROOT/prefixes/steam-no-tso-phase6}
STEAM_DIR="$PREFIX/drive_c/Program Files (x86)/Steam"
CEF_DIR="$STEAM_DIR/bin/cef/cef.win64"
STEAM_EXE="$STEAM_DIR/steam.exe"
WRAPPER_SOURCE="$METALSHARP_ROOT/app/bundles/steamwebhelper.exe"
WRAPPER="$CEF_DIR/steamwebhelper.exe"
REAL_HELPER="$CEF_DIR/steamwebhelper_real.exe"
WRAPPER_SHA256=f46a1e8c39c850ba22861f63559f13b4f68557acf04a92e6d1b899769b2ea1f9
LOG_DIR="$VKMT_ROOT/build/no-tso-phase6"
LOG="$LOG_DIR/steam-metalsharp-compatible.log"

test -x "$BUILD/wine"
test -x "$BUILD/server/wineserver"
test -f "$STEAM_EXE"
test -f "$WRAPPER_SOURCE"
test "$(shasum -a 256 "$WRAPPER_SOURCE" | awk '{print $1}')" = "$WRAPPER_SHA256"

mkdir -p "$LOG_DIR"

# Steam updates replace the wrapper with a new real helper. Preserve that
# updated helper before restoring MetalSharp's small forwarding executable.
if [[ -f "$WRAPPER" && $(stat -f%z "$WRAPPER") -gt 100000 ]]; then
    install -m 0755 "$WRAPPER" "$REAL_HELPER"
fi
test -f "$REAL_HELPER"
test $(stat -f%z "$REAL_HELPER") -gt 100000
install -m 0755 "$WRAPPER_SOURCE" "$WRAPPER"
test "$(shasum -a 256 "$WRAPPER" | awk '{print $1}')" = "$WRAPPER_SHA256"

export WINEPREFIX="$PREFIX"
export WINEBUILDDIR="$BUILD"
source "$VKMT_ROOT/scripts/vkmt-runtime-env.sh"

export WINEBOOTSTRAPMODE=1
export FEX_TSOENABLED=0
export FEX_VECTORTSOENABLED=0
export FEX_MEMCPYSETTSOENABLED=0
export VKMT_STEAM_DISABLE_STACK_PROFILER=0
export VKMT_STEAM_BOOTSTRAP_WAKE_RECOVERY=0
export WINEDEBUG=-all
export WINEDEBUGGER=none
export MS_FWD_COMPAT_GL_CTX=1

"$BUILD/wine" "$STEAM_EXE" \
    -no-cef-sandbox \
    -cef-single-process \
    -noverifyfiles \
    -no-dwrite >>"$LOG" 2>&1
"$BUILD/server/wineserver" -w
