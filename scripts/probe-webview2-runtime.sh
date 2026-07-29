#!/bin/bash
# Prove pinned WebView2 fixed runtimes on x86_64 and i386 in one fresh prefix.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
RUNS="$VKMT/build/probe-runs"
TOOLCHAIN="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
WV2="$VKMT/third_party/webview2-149.0.4022.98"
PROBES="$VKMT/build/browser-probes/webview2"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"

"$VKMT/scripts/fetch-webview2-runtime.sh"
mkdir -p "$PROBES/x64" "$PROBES/i386" "$RUNS"
"$TOOLCHAIN/x86_64-w64-mingw32-g++" -std=c++17 -O2 -municode -static \
  -I"$WV2/sdk/build/native/include" \
  "$VKMT/test/browser/webview2_fixed_probe.cpp" -lole32 -luuid -lwinhttp \
  -o "$PROBES/x64/webview2_fixed_probe.exe"
"$TOOLCHAIN/i686-w64-mingw32-g++" -std=c++17 -O2 -municode -static \
  -I"$WV2/sdk/build/native/include" \
  "$VKMT/test/browser/webview2_fixed_probe.cpp" -lole32 -luuid -lwinhttp \
  -o "$PROBES/i386/webview2_fixed_probe.exe"

run_root="$(mktemp -d "$RUNS/webview2-runtime.XXXXXX")"
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
      WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS='--no-sandbox --disable-gpu-compositing --autoplay-policy=no-user-gesture-required --ignore-certificate-errors --allow-insecure-localhost' \
      WINEDEBUG="${VKMT_WEBVIEW2_WINEDEBUG:-+process}" \
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
mkdir -p "$run_root/https"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=127.0.0.1 \
  -keyout "$run_root/https/key.pem" -out "$run_root/https/cert.pem" \
  >"$run_root/https/cert.log" 2>&1
openssl s_server -quiet -www -accept 127.0.0.1:19443 \
  -key "$run_root/https/key.pem" -cert "$run_root/https/cert.pem" \
  >"$run_root/https/server.log" 2>&1 &
https_pid=$!
for dll in xtajit64 xtajit wow64 wow64win; do
  install -m 0644 "$BUILD/dlls/$dll/aarch64-windows/$dll.dll" \
    "$prefix/drive_c/windows/system32/$dll.dll"
done
while IFS= read -r dll; do
  install -m 0644 "$dll" "$prefix/drive_c/windows/syswow64/$(basename "$dll")"
done < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)

"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
run_wine "$run_root/wineboot.log" "${VKMT_WEBVIEW2_BOOT_TIMEOUT:-120}s" \
  "$WINEBOOT" --init
stop_server
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"

for spec in x64:x64 i386:x86; do
  IFS=: read -r arch runtime_arch <<<"$spec"
  case ",${VKMT_WEBVIEW2_ARCHES:-x64,i386}," in
    *",$arch,"*) ;;
    *) continue ;;
  esac
  client="$run_root/client-$arch"
  runtime="$WV2/runtime-$runtime_arch"
  mkdir -p "$client" "$run_root/user-data-$arch"
  install -m 0755 "$PROBES/$arch/webview2_fixed_probe.exe" "$client/"
  install -m 0644 "$WV2/sdk/build/native/$runtime_arch/WebView2Loader.dll" "$client/"
  run_wine "$run_root/$arch.log" "${VKMT_WEBVIEW2_PROBE_TIMEOUT:-120}s" \
    "$client/webview2_fixed_probe.exe" \
    "$(winpath "$runtime")" "$(winpath "$run_root/user-data-$arch")" \
    "https://127.0.0.1:19443/"
  stop_server
  grep -q WEBVIEW2_HTTPS_TRANSPORT_OK "$run_root/$arch.log"
  grep -Eq 'WEBVIEW2_HTTPS_INPUT_AUDIO_PIXEL_OK|WEBVIEW2_ENV_CONTROLLER_RENDERER_BOOTSTRAP_OK' \
    "$run_root/$arch.log"
  grep -Eq 'msedgewebview2.exe.*--type=renderer' "$run_root/$arch.log"
  grep -Eq 'msedgewebview2.exe.*--type=(gpu-process|utility)' "$run_root/$arch.log"
  if grep -q WEBVIEW2_HTTPS_INPUT_AUDIO_PIXEL_OK "$run_root/$arch.log"; then
    level=FULL
  else
    level=BOOTSTRAP
  fi
  echo "WEBVIEW2_$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')_FIXED_RUNTIME_${level}_OK"
done

echo "WEBVIEW2_FIXED_${VKMT_WEBVIEW2_ARCHES:-x64,i386}_ALL_OK" | tr '[:lower:],' '[:upper:]_'
