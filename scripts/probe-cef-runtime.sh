#!/bin/bash
# Prove pinned CEF 109, the MetalSharp launcher wrapper, and child hook for
# x86_64 and i386/WoW64 in one disposable native-ARM64 Wine prefix.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
RUNS="$VKMT/build/probe-runs"
TOOLCHAIN="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
VERSION="${VKMT_CEF_VERSION:-109.1.18+gf1c41e4+chromium-109.0.5414.120}"
CEF="$VKMT/third_party/cef-$VERSION"
COMPAT="$VKMT/build/cef-compat"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"

test -d "$CEF/windows32/Release" && test -d "$CEF/windows64/Release" ||
  "$VKMT/scripts/fetch-cef-runtime.sh"
"$VKMT/scripts/build-metalsharp-cef-compat.sh"
mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/cef-runtime.XXXXXX")"
prefix="$run_root/prefix"
https_pid=
evidence_dir="${VKMT_CEF_EVIDENCE_DIR:-}"

cleanup()
{
  status=$?
  test -z "$https_pid" || kill "$https_pid" 2>/dev/null || true
  test -z "$https_pid" || wait "$https_pid" 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  if test -n "$evidence_dir"; then
    mkdir -p "$evidence_dir"
    find "$run_root" -maxdepth 1 -type f -exec cp -p {} "$evidence_dir/" \;
    test ! -d "$run_root/https" || cp -R "$run_root/https" "$evidence_dir/"
  fi
  case "$run_root" in "$RUNS"/*)
    test "${VKMT_KEEP_PROBE_RUN:-0}" = 1 ||
      find "$run_root" -depth -delete 2>/dev/null || true
  esac
  exit "$status"
}
trap cleanup EXIT

run_wine()
{
  output=$1
  timeout=$2
  shift 2
  env_args=(
    WINEPREFIX="$prefix"
    WINEBUILDDIR="$BUILD"
    WINEBOOTSTRAPMODE=1
    DYLD_LIBRARY_PATH="$BUILD/dlls/winecoreaudio.drv:$BUILD/dlls/secur32:$BUILD/dlls/ntdll:$BUILD/dlls/win32u${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
    WINEDLLOVERRIDES="${VKMT_CEF_WINEDLLOVERRIDES:-}"
    WINEDEBUG="${VKMT_CEF_WINEDEBUG:--all}"
    FEX_TSOENABLED=0
    FEX_VECTORTSOENABLED=0
    FEX_MEMCPYSETTSOENABLED=0
    FEX_MULTIBLOCK=1
    FEX_MAXINST=5000
  )
  test "${VKMT_CEF_WINE_NO_EXPLORER:-0}" != 1 ||
    env_args+=(WINE_NO_EXPLORER=1)
  test -z "${VKMT_CEF_DXVK_LOG_PATH:-}" ||
    env_args+=(DXVK_LOG_PATH="$VKMT_CEF_DXVK_LOG_PATH" DXVK_LOG_LEVEL=info)
  gtimeout --signal=TERM --kill-after=10s "$timeout" \
    env "${env_args[@]}" "$WINE" "$@" >"$output" 2>&1
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
openssl s_server -quiet -www -accept 127.0.0.1:19445 \
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
VKMT_CEF_WINE_NO_EXPLORER=1 VKMT_CEF_WINEDEBUG=-all \
  run_wine "$run_root/wineboot.log" "${VKMT_CEF_BOOT_TIMEOUT:-120}s" \
    "$WINEBOOT" --init
stop_server
# wineboot populates system32 from the build tree, so restore the pinned
# candidate/runtime provider before verifying or executing a guest.
"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"

for spec in \
  "x86_64:64:$TOOLCHAIN/x86_64-w64-mingw32-gcc" \
  "i386:32:$TOOLCHAIN/i686-w64-mingw32-gcc"; do
  IFS=: read -r arch bits cc <<<"$spec"
  case ",${VKMT_CEF_ARCHES:-x86_64,i386}," in
    *",$arch,"*) ;;
    *) continue ;;
  esac
  arch_marker="$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')"
  client="$run_root/client-$arch"
  release="$CEF/windows$bits/Release"
  case "$arch" in
    x86_64)
      cdp_port=19460
      cdp_transport=page
      angle_args=(--use-gl=angle --use-angle=swiftshader --disable-vulkan)
      start_url=https://127.0.0.1:19445/
      ;;
    i386)
      cdp_port=19461
      cdp_transport=browser
      # CEF's bundled 32-bit SwANGLE Vulkan context is not usable over the
      # Wine/MoltenVK boundary.  OSR does not require a GPU compositor, so use
      # Chromium's software paint path and prevent fallback into SwANGLE.
      angle_args=(--use-gl=disabled --disable-gpu --disable-gpu-compositing
                  --disable-gpu-rasterization --disable-software-rasterizer
                  --disable-vulkan --in-process-gpu
                  --renderer-process-limit=1)
      start_url=data:text/html,VKMT_CEF_I386_OSR
      ;;
  esac
  extra_args=()
  if test -n "${VKMT_CEF_EXTRA_ARGS:-}"; then
    read -r -a extra_args <<<"$VKMT_CEF_EXTRA_ARGS"
  fi

  "$TOOLCHAIN/llvm-readobj" --coff-exports "$release/libcef.dll" \
    >"$run_root/$arch-exports.log"
  for export_name in cef_version_info cef_execute_process cef_initialize \
                     cef_browser_host_create_browser cef_shutdown; do
    grep -q "Name: $export_name" "$run_root/$arch-exports.log"
  done
  echo "CEF_${arch_marker}_EXPORTS_OK"

  mkdir -p "$client"
  for item in "$release"/*; do
    name="$(basename "$item")"
    case "$name" in
      cefclient.exe|chrome_elf.dll|vulkan-1.dll|vk_swiftshader*)
        continue
        ;;
      libEGL.dll|libGLESv2.dll)
        test "$arch" != i386 || continue
        ;;
    esac
    ln -s "$item" "$client/$name"
  done
  if test -d "$CEF/windows$bits/Resources"; then
    for item in "$CEF/windows$bits/Resources"/*; do
      name="$(basename "$item")"
      test -e "$client/$name" || ln -s "$item" "$client/$name"
    done
  fi
  ln -s "$release/cefclient.exe" "$client/cefclient.exe"
  install -m 0644 "$COMPAT/$arch/chrome_elf.dll" "$client/chrome_elf.dll"

  find "$prefix/drive_c/users" -type f \
    \( -name metalsharp-cefchildhook.log -o -name metalsharp-chrome-elf-compat.log \) \
    -exec unlink {} \;
  set +e
  run_wine "$run_root/$arch-client.log" "${VKMT_CEF_CLIENT_WINDOW:-90}s" \
    "$client/cefclient.exe" --no-sandbox --disable-gpu-sandbox \
    "${angle_args[@]}" \
    ${extra_args[@]+"${extra_args[@]}"} \
    --off-screen-rendering-enabled --hide-controls \
    --ignore-certificate-errors --autoplay-policy=no-user-gesture-required \
    "--remote-debugging-port=$cdp_port" \
    "--url=$start_url" \
    "--log-file=$(winpath "$run_root/$arch-cef.log")" &
  client_job=$!
  set -e
  set +e
  gtimeout --signal=TERM --kill-after=10s \
    "${VKMT_CEF_CDP_TIMEOUT:-60}s" \
    node "$VKMT/test/browser/chromium_cdp_probe.mjs" "$cdp_port" \
      "$run_root/$arch-screenshot.png" "https://127.0.0.1:19445/" \
      "$cdp_transport" \
      >"$run_root/$arch-cdp.log" 2>&1
  cdp_status=$?
  set -e
  kill "$client_job" 2>/dev/null || true
  stop_server
  set +e
  wait "$client_job" 2>/dev/null
  client_status=$?
  set -e

  test "$cdp_status" -eq 0
  grep -q CHROMIUM_CDP_HTTPS_AUDIO_OK "$run_root/$arch-cdp.log"
  grep -q CHROMIUM_CDP_INPUT_OK "$run_root/$arch-cdp.log"
  grep -q 'CHROMIUM_CDP_PIXEL_OK .* 17,34,51,255' \
    "$run_root/$arch-cdp.log"
  test -s "$run_root/$arch-screenshot.png"

  elf_log="$(find "$prefix/drive_c/users" -type f -name metalsharp-chrome-elf-compat.log -print -quit)"
  test -f "$elf_log"
  grep -q 'chrome_elf compatibility DLL loaded' "$elf_log"
  grep -Eq 'command: .*--type=(renderer|utility|gpu-process)' "$elf_log"
  test -f "$run_root/$arch-cef.log"
  test -s "$run_root/$arch-cef.log"
  case "$client_status" in
    0|124|143) ;;
    *)
      # Wine may deliver the observation-window TERM to the PE child and
      # return that child's code. Runtime evidence above is authoritative.
      echo "CEF_${arch_marker}_OBSERVATION_EXIT_$client_status"
      ;;
  esac
  echo "CEF_${arch_marker}_SUBPROCESS_RUNTIME_OK"
  echo "CEF_${arch_marker}_OSR_HTTPS_INPUT_AUDIO_PIXEL_OK"
done

echo CEF_X64_I386_ALL_OK
