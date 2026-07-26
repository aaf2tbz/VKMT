#!/bin/bash
# Run a Windows exe in the VKMT test prefix using MetalSharp's wine,
# but with VKMT's MoltenVK (VK_EXT_transform_feedback + robustness2 patches).
set -euo pipefail
VKMT=/Volumes/AverySSD/VKMT
MS_ROOT="$HOME/.metalsharp/runtime/wine"

export WINEPREFIX="${WINEPREFIX:-$VKMT/test/prefix}"
export WINESERVER="$MS_ROOT/bin/wineserver"
export WINELOADER="$MS_ROOT/bin/wine"
export WINEDLLPATH="$MS_ROOT/lib/wine/x86_64-windows:$MS_ROOT/lib/wine/i386-windows"
export WINEDATADIR="$MS_ROOT/share"
# Wine loads optional Unix libraries by soname.  Homebrew's dylib directory
# must be on the fallback path at runtime even though configure found it.
export DYLD_FALLBACK_LIBRARY_PATH="$MS_ROOT/lib:$MS_ROOT/lib/wine/x86_64-unix:/opt/homebrew/lib${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"
export VK_ICD_FILENAMES="$VKMT/test/vkmt_icd.json"
export WINEDEBUG="${WINEDEBUG:--all}"
# vkd3d-proton DLLs staged into the prefix as native
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-d3d12,d3d12core=n,b}"

exec arch -x86_64 "$MS_ROOT/bin/wine" "$@"
