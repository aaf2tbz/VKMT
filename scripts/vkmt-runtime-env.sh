#!/bin/bash
# Source this file before launching the native ARM64 Wine host runtime.
VKMT_RUNTIME_ROOT="${VKMT_RUNTIME_ROOT:-/Volumes/AverySSD/VKMT}"
VKMT_WINE_BUILD="${WINEBUILDDIR:-$VKMT_RUNTIME_ROOT/wine/build-ec}"
VKMT_GST_ROOT="${VKMT_GSTREAMER_RUNTIME:-$VKMT_WINE_BUILD/runtime/gstreamer-arm64}"

test -s "$VKMT_GST_ROOT/MANIFEST.sha256" || {
  echo "Missing verified VKMT GStreamer runtime: $VKMT_GST_ROOT" >&2
  return 1 2>/dev/null || exit 1
}

export DYLD_LIBRARY_PATH="$VKMT_GST_ROOT/lib:$VKMT_WINE_BUILD/dlls/winecoreaudio.drv:$VKMT_WINE_BUILD/dlls/secur32:$VKMT_WINE_BUILD/dlls/ntdll:$VKMT_WINE_BUILD/dlls/win32u${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
export GI_TYPELIB_PATH="$VKMT_GST_ROOT/girepository-1.0${GI_TYPELIB_PATH:+:$GI_TYPELIB_PATH}"
export GST_PLUGIN_PATH_1_0="$VKMT_GST_ROOT/lib/gstreamer-1.0"
export GST_PLUGIN_SYSTEM_PATH_1_0="$VKMT_GST_ROOT/lib/gstreamer-1.0"
export GST_PLUGIN_SCANNER_1_0="$VKMT_GST_ROOT/libexec/gstreamer-1.0/gst-plugin-scanner"
export GST_REGISTRY="${WINEPREFIX:?WINEPREFIX must be set}/.vkmt/gstreamer-registry.bin"

# Chromium's sampling profiler repeatedly suspends translated ARM64EC threads
# and can starve Steam's initial renderer/Mojo handoff.  Wine scopes this to
# steamwebhelper.exe and removes only the optional telemetry switch.
export VKMT_STEAM_DISABLE_STACK_PROFILER="${VKMT_STEAM_DISABLE_STACK_PROFILER:-1}"
