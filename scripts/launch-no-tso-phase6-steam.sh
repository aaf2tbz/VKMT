#!/bin/zsh
# Launch the clean Phase 6 Steam installer as a durable, observation-only run.
set -u

VKMT=/Volumes/AverySSD/VKMT
BUILD="$VKMT/wine/build-ec"
PREFIX="$VKMT/prefixes/steam-no-tso-phase6"
INSTALLER=/Users/averyfelts/Desktop/SteamSetup.exe
STATE="$VKMT/build/no-tso-phase6"
LOG=/Users/averyfelts/Library/Logs/VKMT/no-tso-phase6-installer.log

mkdir -p "$STATE"
exec >>"$LOG" 2>&1
print -r -- "PHASE6_LAUNCH_UTC=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
print -r -- "PHASE6_PREFIX=$PREFIX"
print -r -- "FEX_TSOENABLED=0"
print -r -- "FEX_VECTORTSOENABLED=0"
print -r -- "FEX_MEMCPYSETTSOENABLED=0"
print -r -- "VKMT_STEAM_BOOTSTRAP_WAKE_RECOVERY=0"
print -r -- "VKMT_STEAM_HANDOFF_NOTIFY=1"

if [[ ! -f "$PREFIX/system.reg" || ! -f "$INSTALLER" ]]; then
    print -u2 -- "PHASE6_LAUNCH_INPUT_MISSING"
    exit 2
fi

export WINEPREFIX="$PREFIX"
export WINEBUILDDIR="$BUILD"
source "$VKMT/scripts/vkmt-runtime-env.sh" || exit 3

env \
  WINEPREFIX="$PREFIX" \
  WINEBUILDDIR="$BUILD" \
  WINEBOOTSTRAPMODE=1 \
  DYLD_LIBRARY_PATH="$DYLD_LIBRARY_PATH" \
  GI_TYPELIB_PATH="$GI_TYPELIB_PATH" \
  GST_PLUGIN_PATH_1_0="$GST_PLUGIN_PATH_1_0" \
  GST_PLUGIN_SYSTEM_PATH_1_0="$GST_PLUGIN_SYSTEM_PATH_1_0" \
  GST_PLUGIN_SCANNER_1_0="$GST_PLUGIN_SCANNER_1_0" \
  GST_REGISTRY="$GST_REGISTRY" \
  FEX_TSOENABLED=0 \
  FEX_VECTORTSOENABLED=0 \
  FEX_MEMCPYSETTSOENABLED=0 \
  VKMT_STEAM_BOOTSTRAP_WAKE_RECOVERY=0 \
  VKMT_STEAM_HANDOFF_NOTIFY=1 \
  WINEDEBUG=-all \
  WINEDEBUGGER=none \
  MS_FWD_COMPAT_GL_CTX=1 \
  "$BUILD/wine" "$INSTALLER"
exit_code=$?
print -r -- "PHASE6_INSTALLER_EXIT=$exit_code"
exit "$exit_code"
