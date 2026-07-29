#!/bin/bash
# Prove pinned Electron x64 and i386 renderer/runtime behavior in one prefix.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
RUNS="$VKMT/build/probe-runs"
ELECTRON="$VKMT/third_party/electron-42.7.1"
APP="$VKMT/test/browser/electron"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"

"$VKMT/scripts/fetch-electron-runtime.sh"
mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/electron-runtime.XXXXXX")"
prefix="$run_root/prefix"
https_pid=

cleanup()
{
  status=$?
  test -z "$https_pid" || kill "$https_pid" 2>/dev/null || true
  test -z "$https_pid" || wait "$https_pid" 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  case "$run_root" in "$RUNS"/*)
    test "${VKMT_KEEP_PROBE_RUN:-0}" = 1 ||
      /usr/bin/trash "$run_root" 2>/dev/null || true
  esac
  exit "$status"
}
trap cleanup EXIT

run_wine()
{
  output=$1
  timeout_seconds=$2
  shift 2
  gtimeout --signal=TERM --kill-after=10s "$timeout_seconds" \
    env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
      DYLD_LIBRARY_PATH="$BUILD/dlls/winecoreaudio.drv:$BUILD/dlls/secur32:$BUILD/dlls/ntdll:$BUILD/dlls/win32u${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
      WINEDEBUG="${VKMT_ELECTRON_WINEDEBUG:-+process}" \
      "$WINE" "$@" >"$output" 2>&1
}

stop_server()
{
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
}

winpath()
{
  printf 'Z:%s' "${1//\//\\}"
}

mkdir -p "$prefix/drive_c/windows/system32" "$prefix/drive_c/windows/syswow64"
for dll in xtajit64 xtajit wow64 wow64win; do
  install -m 0644 "$BUILD/dlls/$dll/aarch64-windows/$dll.dll" \
    "$prefix/drive_c/windows/system32/$dll.dll"
done
while IFS= read -r dll; do
  install -m 0644 "$dll" "$prefix/drive_c/windows/syswow64/$(basename "$dll")"
done < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)

mkdir -p "$run_root/https"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=127.0.0.1 \
  -keyout "$run_root/https/key.pem" -out "$run_root/https/cert.pem" \
  >"$run_root/https/cert.log" 2>&1
openssl s_server -quiet -www -accept 127.0.0.1:19444 \
  -key "$run_root/https/key.pem" -cert "$run_root/https/cert.pem" \
  >"$run_root/https/server.log" 2>&1 &
https_pid=$!

"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
run_wine "$run_root/wineboot.log" "${VKMT_ELECTRON_BOOT_TIMEOUT:-120}s" \
  "$WINEBOOT" --init
stop_server
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"

for spec in x64:x64 i386:ia32; do
  IFS=: read -r arch runtime_arch <<<"$spec"
  case ",${VKMT_ELECTRON_ARCHES:-x64,i386}," in
    *",$arch,"*) ;;
    *) continue ;;
  esac
  result="$run_root/$arch-result.txt"
  log="$run_root/$arch.log"
  VKMT_ELECTRON_RESULT="$(winpath "$result")" \
  VKMT_ELECTRON_HTTPS_URL="https://127.0.0.1:19444/" \
    run_wine "$log" "${VKMT_ELECTRON_PROBE_TIMEOUT:-120}s" \
      "$ELECTRON/windows-$runtime_arch/electron.exe" "$(winpath "$APP")"
  stop_server
  grep -q ELECTRON_HTTPS_INPUT_AUDIO_PIXEL_OK "$result"
  grep -Eq 'electron.exe.*--type=renderer' "$log"
  grep -Eq 'electron.exe.*--type=(gpu-process|utility)' "$log"
  echo "ELECTRON_$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')_OK"
done

echo "ELECTRON_${VKMT_ELECTRON_ARCHES:-x64,i386}_ALL_OK" | tr '[:lower:],' '[:upper:]_'
