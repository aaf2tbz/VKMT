#!/bin/zsh
# Launch an already installed Steam client once after SteamSetup has completed.
# This is intentionally not a launchd keepalive job: a normal exit,
# cancellation, or crash must never cause SteamSetup or Steam to be relaunched.
set -euo pipefail

VKMT=/Volumes/AverySSD/VKMT
BUILD="$VKMT/wine/build-ec"
PREFIX="$VKMT/prefixes/steam-allarch"
STEAM_EXE="$PREFIX/drive_c/Program Files (x86)/Steam/Steam.exe"

if [[ ! -f "$STEAM_EXE" ]]; then
    print -u2 -- "VKMT Steam recovery: installed Steam.exe is not present; run SteamSetup normally first."
    exit 2
fi

exec env \
    WINEPREFIX="$PREFIX" \
    WINEBUILDDIR="$BUILD" \
    DYLD_LIBRARY_PATH="$BUILD/dlls/winecoreaudio.drv:$BUILD/dlls/secur32:$BUILD/dlls/ntdll:$BUILD/dlls/win32u${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
    FEX_TSOENABLED=0 \
    FEX_VECTORTSOENABLED=0 \
    FEX_MEMCPYSETTSOENABLED=0 \
    VKMT_STEAM_BOOTSTRAP_WAKE_RECOVERY=1 \
    WINEDEBUG=-all \
    WINEDEBUGGER=none \
    MS_FWD_COMPAT_GL_CTX=1 \
    "$BUILD/wine" 'C:\\Program Files (x86)\\Steam\\Steam.exe'
