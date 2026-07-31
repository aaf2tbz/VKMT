#!/bin/zsh
# Run one installed Steam bootstrap session and repair its known final handoff.
# The helper never retries downloads or relaunches after failures: it performs
# exactly one restart, and only after Steam itself records a completed update.
set -euo pipefail

VKMT=/Volumes/AverySSD/VKMT
BUILD="$VKMT/wine/build-ec"
PREFIX="$VKMT/prefixes/steam-allarch"
STEAM_EXE="$PREFIX/drive_c/Program Files (x86)/Steam/Steam.exe"
BOOTSTRAP_LOG="$PREFIX/drive_c/Program Files (x86)/Steam/logs/bootstrap_log.txt"

[[ -f "$STEAM_EXE" ]] || { print -u2 -- 'VKMT Steam: Steam.exe is not installed.'; exit 2; }

launch_client()
{
    env WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" \
        DYLD_LIBRARY_PATH="$BUILD/dlls/winecoreaudio.drv:$BUILD/dlls/secur32:$BUILD/dlls/ntdll:$BUILD/dlls/win32u${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
        FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
        VKMT_STEAM_BOOTSTRAP_WAKE_RECOVERY=1 WINEDEBUG=-all WINEDEBUGGER=none \
        MS_FWD_COMPAT_GL_CTX=1 "$BUILD/wine" 'C:\\Program Files (x86)\\Steam\\Steam.exe'
}

# Only bytes written after this invocation are eligible to trigger a handoff.
offset=0
[[ -f "$BOOTSTRAP_LOG" ]] && offset=$(stat -f %z "$BOOTSTRAP_LOG")
launch_client &

# Keep observing extraction and installation, but do not wake either phase.
for _ in {1..1800}; do
    if [[ -f "$BOOTSTRAP_LOG" ]]; then
        size=$(stat -f %z "$BOOTSTRAP_LOG")
        if (( size > offset )); then
            update=$(tail -c +$((offset + 1)) "$BOOTSTRAP_LOG")
            offset=$size
            if [[ "$update" == *'Update complete, launching Steam...' ]]; then
                sleep 1
                env WINEPREFIX="$PREFIX" "$BUILD/server/wineserver" -k || true
                env WINEPREFIX="$PREFIX" "$BUILD/server/wineserver" -w || true
                launch_client
                exit $?
            fi
        fi
    fi
    sleep 1
done

print -u2 -- 'VKMT Steam: no completed-update handoff was observed within 30 minutes.'
exit 3
