#!/bin/bash
# Genuine visible Chromium/CEF acceptance gate. This intentionally does not
# use CEF off-screen rendering or hidden browser controls.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"

export VKMT_CEF_ARCHES="${VKMT_CEF_ARCHES:-x86_64}"
export VKMT_CEF_RENDER_MODE=windowed
export VKMT_CEF_CLIENT_WINDOW="${VKMT_CEF_CLIENT_WINDOW:-120}"
export VKMT_CEF_CDP_TIMEOUT="${VKMT_CEF_CDP_TIMEOUT:-90}"

"$VKMT/scripts/probe-cef-runtime.sh"
