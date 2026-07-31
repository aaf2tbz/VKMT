#!/bin/zsh
# Launch SteamSetup through the authoritative SSD Wine tree. This is invoked
# by a per-user launchd job so the GUI process is not tied to a shell/PTY.
set -euo pipefail

VKMT=/Volumes/AverySSD/VKMT
BUILD="$VKMT/wine/build-ec"
PREFIX="$VKMT/prefixes/steam-allarch"
INSTALLER=/Users/averyfelts/Desktop/SteamSetup.exe
LOG="$VKMT/logs/steam-ssd-installer-launchd.log"

exec >>"$LOG" 2>&1
print -r -- "launch-steam-setup-ssd: $(date)"
set -x

exec env \
  WINEPREFIX="$PREFIX" \
  WINEBUILDDIR="$BUILD" \
  WINEBOOTSTRAPMODE=1 \
  DYLD_LIBRARY_PATH="$BUILD/dlls/winecoreaudio.drv:$BUILD/dlls/secur32:$BUILD/dlls/ntdll:$BUILD/dlls/win32u${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
  FEX_TSOENABLED=0 \
  FEX_VECTORTSOENABLED=0 \
  FEX_MEMCPYSETTSOENABLED=0 \
  WINEDEBUG='+process,+loaddll,+seh' \
  WINEDEBUGGER=none \
  MS_FWD_COMPAT_GL_CTX=1 \
  "$BUILD/wine" "$INSTALLER"
