#!/bin/bash
# Source this file before launching the native ARM64 Wine host runtime.
VKMT_RUNTIME_ROOT="${VKMT_RUNTIME_ROOT:-/Volumes/AverySSD/VKMT}"
VKMT_WINE_BUILD="${WINEBUILDDIR:-$VKMT_RUNTIME_ROOT/wine/build-ec}"
VKMT_GST_ROOT="${VKMT_GSTREAMER_RUNTIME:-$VKMT_WINE_BUILD/runtime/gstreamer-arm64}"

test -s "$VKMT_GST_ROOT/MANIFEST.sha256" || {
  echo "Missing verified VKMT GStreamer runtime: $VKMT_GST_ROOT" >&2
  return 1 2>/dev/null || exit 1
}

# Keep host resolution hermetic and generation-stable.  Inheriting arbitrary
# Homebrew or user search paths both invalidates warm lookups and can silently
# replace the bundled dependency closure.
export DYLD_LIBRARY_PATH="$VKMT_GST_ROOT/lib:$VKMT_WINE_BUILD/dlls/winecoreaudio.drv:$VKMT_WINE_BUILD/dlls/secur32:$VKMT_WINE_BUILD/dlls/ntdll:$VKMT_WINE_BUILD/dlls/win32u"
export GI_TYPELIB_PATH="$VKMT_GST_ROOT/girepository-1.0"
export GST_PLUGIN_PATH_1_0="$VKMT_GST_ROOT/lib/gstreamer-1.0"
export GST_PLUGIN_SYSTEM_PATH_1_0="$VKMT_GST_ROOT/lib/gstreamer-1.0"
export GST_PLUGIN_SCANNER_1_0="$VKMT_GST_ROOT/libexec/gstreamer-1.0/gst-plugin-scanner"
export GST_REGISTRY="${WINEPREFIX:?WINEPREFIX must be set}/.vkmt/gstreamer-registry.bin"

# Persistent translated-code caches are part of the accepted runtime.  The
# provider itself rejects every TSO mode, but export the production contract
# explicitly so launchers cannot inherit stale user/session values.
export FEX_ENABLECODECACHINGWIP="${FEX_ENABLECODECACHINGWIP:-1}"
export FEX_TSOENABLED=0
export FEX_VECTORTSOENABLED=0
export FEX_MEMCPYSETTSOENABLED=0

# Keep every graphics translator in one versioned, per-prefix cache generation.
# The manifest is created during prefix staging; a previously unseen prefix is
# initialized lazily once and subsequent launches only source this small file.
source "$VKMT_RUNTIME_ROOT/scripts/vkmt-gpu-cache-env.sh"

# Chromium's sampling profiler repeatedly suspends translated ARM64EC threads
# and can starve Steam's initial renderer/Mojo handoff.  Wine scopes this to
# steamwebhelper.exe and removes only the optional telemetry switch.
export VKMT_STEAM_DISABLE_STACK_PROFILER="${VKMT_STEAM_DISABLE_STACK_PROFILER:-1}"
