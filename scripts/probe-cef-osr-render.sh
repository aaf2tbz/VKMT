#!/bin/bash
# Deterministic CEF 109 windowless/OSR pixel gate on the canonical prefix.
# This is intentionally separate from the legacy cefclient/CDP probe: cefclient
# is windowed, while this host owns a CEF render handler and can prove paint.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd -P)"
PREFIX="${VKMT_CEF_OSR_PREFIX:-$VKMT/build/probe-runs/phase-a-graphics-prefix}"
EVIDENCE="${VKMT_CEF_OSR_EVIDENCE_DIR:-$VKMT/docs/validation/cef-osr-render-p8}"
URL="${VKMT_CEF_OSR_URL:-}"
test -n "$URL" || URL='data:text/html,<style>body{margin:0;background:rgb(17,34,51)}div{position:absolute;left:100px;top:100px;color:white;font-size:64px;font-family:Arial}</style><div>VKMT_TEXT_OK</div>'
TIMEOUT="${VKMT_CEF_OSR_TIMEOUT:-60}"

case "$PREFIX" in /*) ;; *) echo "CEF OSR prefix must be absolute" >&2; exit 2;; esac
case "$EVIDENCE" in /*) ;; *) echo "CEF OSR evidence directory must be absolute" >&2; exit 2;; esac
case "$TIMEOUT" in ''|*[!0-9]*) echo "CEF OSR timeout must be integer seconds" >&2; exit 2;; esac
test -f "$PREFIX/.vkmt/receipt.json" || {
  echo "CEF OSR requires the existing receipt-backed prefix: $PREFIX" >&2
  exit 1
}

mkdir -p "$EVIDENCE"
set +e
VKMT_BROWSER_PREFIX="$PREFIX" \
VKMT_BROWSER_LOG_DIR="$EVIDENCE" \
VKMT_BROWSER_URL="$URL" \
VKMT_BROWSER_WINEDEBUG="${VKMT_CEF_OSR_WINEDEBUG:--all}" \
VKMT_BROWSER_WAIT_FOR_RENDER=1 \
VKMT_BROWSER_RENDER_TIMEOUT="$TIMEOUT" \
  "$VKMT/scripts/launch-vkmt-cef-browser.sh" \
  >"$EVIDENCE/driver.log" 2>&1
status=$?
set -e

browser_log="$(find "$EVIDENCE" -maxdepth 1 -type f -name 'browser-*.log' -print | LC_ALL=C sort | tail -1)"
test -n "$browser_log" || { echo "CEF OSR browser log is missing" >&2; exit 1; }
if test "$status" -ne 0; then
  echo "CEF OSR launcher failed (status=$status); log=$browser_log" >&2
  exit "$status"
fi
grep -q 'VKMT_BROWSER_PAINT_BGRA_51_34_17_255' "$browser_log"
grep -q 'VKMT_BROWSER_TEXT_PIXEL_OK' "$browser_log"
grep -q 'VKMT_BROWSER_PIXEL_OK' "$browser_log"
"$VKMT/scripts/vkmt-prefix" verify --prefix "$PREFIX" >"$EVIDENCE/prefix-verify.log"

echo "CEF_X86_64_OSR_PIXEL_OK log=$browser_log text=VKMT_TEXT_OK"
echo "CEF_X86_64_OSR_RENDER_OK prefix=$PREFIX evidence=$EVIDENCE"
