#!/bin/bash
# Prove pinned CEF 109, the MetalSharp launcher wrapper, and child hook for
# x86_64 and i386/WoW64 in one prepared native-ARM64 Wine prefix. Pass
# --prefix to reuse a receipt-backed prefix; without it the legacy disposable
# probe mode is retained.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_ROOT="${VKMT_RUNTIME_ROOT:-$VKMT}"
BUILD="${VKMT_WINE_BUILD:-$RUNTIME_ROOT/wine/build-ec}"
RUNS="${VKMT_PROBE_RUNS:-$VKMT/build/probe-runs}"
TOOLCHAIN="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
VERSION="${VKMT_CEF_VERSION:-109.1.18+gf1c41e4+chromium-109.0.5414.120}"
CEF="$VKMT/third_party/cef-$VERSION"
COMPAT="$VKMT/build/cef-compat"
PROVIDER_SCRIPT="${VKMT_PROVIDER_SCRIPT:-$RUNTIME_ROOT/scripts/stage-runtime-providers.sh}"
RUNTIME_ENV="${VKMT_RUNTIME_ENV:-$RUNTIME_ROOT/scripts/vkmt-runtime-env.sh}"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
PREFIX_ARG="${VKMT_CEF_PREFIX:-}"

usage()
{
  echo "usage: $0 [--prefix EXISTING_VKMT_PREFIX]" >&2
  exit 2
}

while test "$#" -gt 0; do
  case "$1" in
    --prefix)
      test "$#" -ge 2 || usage
      PREFIX_ARG=$2
      shift 2
      ;;
    *) usage ;;
  esac
done

use_existing_prefix=0
if test -n "$PREFIX_ARG"; then
  case "$PREFIX_ARG" in /*) ;; *) echo "CEF prefix must be absolute" >&2; exit 2 ;; esac
  PREFIX_ARG="$(cd "$PREFIX_ARG" && pwd -P)"
  test -f "$PREFIX_ARG/.vkmt/receipt.json" || {
    echo "CEF prefix is not a receipt-backed VKMT prefix: $PREFIX_ARG" >&2
    exit 1
  }
  use_existing_prefix=1
fi

test -d "$CEF/windows32/Release" && test -d "$CEF/windows64/Release" ||
  "$VKMT/scripts/fetch-cef-runtime.sh"
test -x "$WINE" && test -x "$WINESERVER" && test -f "$WINEBOOT"
test -x "$PROVIDER_SCRIPT" && test -f "$RUNTIME_ENV"
"$VKMT/scripts/build-metalsharp-cef-compat.sh"
mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/cef-runtime.XXXXXX")"
prefix="${PREFIX_ARG:-$run_root/prefix}"
trace_dir="${VKMT_CEF_TRACE_DIR:-$run_root/traces}"
mkdir -p "$trace_dir"
https_pid=
tls_proxy_pid=
evidence_dir="${VKMT_CEF_EVIDENCE_DIR:-}"
https_accept="${VKMT_CEF_HTTPS_ACCEPT:-127.0.0.1:19445}"
https_url="${VKMT_CEF_HTTPS_URL:-https://127.0.0.1:19445/}"
render_mode="${VKMT_CEF_RENDER_MODE:-osr}"
case "$render_mode" in
  osr|windowed) ;;
  *) echo "unsupported VKMT_CEF_RENDER_MODE=$render_mode" >&2; exit 2 ;;
esac

cleanup()
{
  status=$?
  test -z "$https_pid" || kill "$https_pid" 2>/dev/null || true
  test -z "$https_pid" || wait "$https_pid" 2>/dev/null || true
  test -z "$tls_proxy_pid" || kill "$tls_proxy_pid" 2>/dev/null || true
  test -z "$tls_proxy_pid" || wait "$tls_proxy_pid" 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  if test -n "$evidence_dir"; then
    mkdir -p "$evidence_dir"
    find "$run_root" -maxdepth 1 -type f -exec cp -p {} "$evidence_dir/" \;
    if test -d "$run_root/https"; then
      mkdir -p "$evidence_dir/https"
      # The one-run test key is disposable secret material, not evidence.
      # Preserve the public certificate and diagnostic logs only.
      find "$run_root/https" -maxdepth 1 -type f ! -name key.pem \
        -exec cp -p {} "$evidence_dir/https/" \;
    fi
    if test -d "$trace_dir"; then
      rm -rf "$evidence_dir/traces"
      cp -R "$trace_dir" "$evidence_dir/traces"
    fi
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
    FEX_MULTIBLOCK="${VKMT_CEF_FEX_MULTIBLOCK:-1}"
    FEX_MAXINST="${VKMT_CEF_FEX_MAXINST:-5000}"
    VKMT_WOW64_VM_TRACE="${VKMT_WOW64_VM_TRACE:-1}"
    VKMT_CEF_SOFTWARE_CHILDREN="${VKMT_CEF_SOFTWARE_CHILDREN:-0}"
    VKMT_CEF_DISABLE_CHILD_HOOK="${VKMT_CEF_DISABLE_CHILD_HOOK:-0}"
    VKMT_PERF_RUN_ID="${VKMT_PERF_RUN_ID:-cef-bootstrap}"
    VKMT_PERF_TRACE_HOST_DIR="$trace_dir"
  )
  test "${VKMT_CEF_WINE_NO_EXPLORER:-0}" != 1 ||
    env_args+=(WINE_NO_EXPLORER=1)
  test -z "${VKMT_CEF_DXVK_LOG_PATH:-}" ||
    env_args+=(DXVK_LOG_PATH="$VKMT_CEF_DXVK_LOG_PATH" DXVK_LOG_LEVEL=info)
  gtimeout --signal=TERM --kill-after=10s "$timeout" \
    env "${env_args[@]}" "$WINE" "$@" >"$output" 2>&1
}

duration_arg()
{
  case "$1" in
    *s|*m|*h) printf '%s' "$1" ;;
    *) printf '%ss' "$1" ;;
  esac
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

prefix_log()
{
  find "$prefix/drive_c/users" -type f -name "$1" -print -quit
}

mkdir -p "$prefix/drive_c/windows/system32" "$prefix/drive_c/windows/syswow64"
mkdir -p "$run_root/https"
case "${VKMT_CEF_CERT_KEY_TYPE:-rsa}" in
  ec)
    openssl req -x509 -newkey ec \
      -pkeyopt "ec_paramgen_curve:${VKMT_CEF_CERT_EC_CURVE:-P-256}" \
      -nodes -days 1 -subj /CN=127.0.0.1 \
      -keyout "$run_root/https/key.pem" -out "$run_root/https/cert.pem" \
      >"$run_root/https/cert.log" 2>&1
    ;;
  ed25519)
    openssl req -x509 -newkey ed25519 -nodes -days 1 -subj /CN=127.0.0.1 \
      -keyout "$run_root/https/key.pem" -out "$run_root/https/cert.pem" \
      >"$run_root/https/cert.log" 2>&1
    ;;
  rsa)
    openssl req -x509 -newkey "rsa:${VKMT_CEF_CERT_RSA_BITS:-2048}" \
      -nodes -days 1 -subj /CN=127.0.0.1 \
      -keyout "$run_root/https/key.pem" -out "$run_root/https/cert.pem" \
      >"$run_root/https/cert.log" 2>&1
    ;;
  *)
    echo "unsupported VKMT_CEF_CERT_KEY_TYPE=$VKMT_CEF_CERT_KEY_TYPE" >&2
    exit 2
    ;;
esac
openssl_server_args=()
if test -n "${VKMT_CEF_OPENSSL_SERVER_ARGS:-}"; then
  read -r -a openssl_server_args <<<"$VKMT_CEF_OPENSSL_SERVER_ARGS"
fi
if test "${VKMT_CEF_CERT_CHAIN_COPIES:-0}" -gt 0; then
  chain_file="$run_root/https/chain.pem"
  : >"$chain_file"
  chain_copy=0
  while test "$chain_copy" -lt "$VKMT_CEF_CERT_CHAIN_COPIES"; do
    openssl x509 -in "$run_root/https/cert.pem" -outform PEM >>"$chain_file"
    chain_copy=$((chain_copy + 1))
  done
  openssl_server_args+=(-cert_chain "$chain_file")
fi
if test "${#openssl_server_args[@]}" -gt 0; then
  openssl s_server -quiet -www -accept "$https_accept" \
    "${openssl_server_args[@]}" \
    -key "$run_root/https/key.pem" -cert "$run_root/https/cert.pem" \
    >"$run_root/https/server.log" 2>&1 &
else
  # macOS still ships Bash 3.2, where expanding an empty array under `set -u`
  # raises an unbound-variable error. Keep the no-extra-options path explicit.
  openssl s_server -quiet -www -accept "$https_accept" \
    -key "$run_root/https/key.pem" -cert "$run_root/https/cert.pem" \
    >"$run_root/https/server.log" 2>&1 &
fi
https_pid=$!
if test -n "${VKMT_CEF_TLS_PROXY_DELAY_MS:-}"; then
  node "$VKMT/test/browser/tls_delay_proxy.mjs" \
    "${VKMT_CEF_TLS_PROXY_PORT:-19446}" \
    "${VKMT_CEF_TLS_PROXY_UPSTREAM_HOST:-127.0.0.1}" \
    "${VKMT_CEF_TLS_PROXY_UPSTREAM_PORT:-19445}" \
    "$VKMT_CEF_TLS_PROXY_DELAY_MS" "${VKMT_CEF_TLS_PROXY_CHUNK:-512}" \
    >"$run_root/https/proxy.log" 2>&1 &
  tls_proxy_pid=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    grep -q VKMT_TLS_DELAY_PROXY_READY "$run_root/https/proxy.log" 2>/dev/null && break
    sleep 0.1
  done
  grep -q VKMT_TLS_DELAY_PROXY_READY "$run_root/https/proxy.log"
fi
if test "$use_existing_prefix" = 1; then
  # Existing prefixes are authoritative. Stage only the rebuilt WoW64 bridge;
  # the i386 closure and other native bridges are already receipt-backed.
  "$VKMT/scripts/vkmt-prefix" sync-wow64 --prefix "$prefix"
else
  for dll in xtajit64 xtajit wow64 wow64win; do
    install -m 0644 "$BUILD/dlls/$dll/aarch64-windows/$dll.dll" \
      "$prefix/drive_c/windows/system32/$dll.dll"
  done
  while IFS= read -r dll; do
    install -m 0644 "$dll" "$prefix/drive_c/windows/syswow64/$(basename "$dll")"
  done < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)
fi

export VKMT_RUNTIME_ROOT="$RUNTIME_ROOT"
export WINEBUILDDIR="$BUILD"
export WINEPREFIX="$prefix"
. "$RUNTIME_ENV"
if test "$use_existing_prefix" = 0 || test "${VKMT_CEF_RESTAGE_PROVIDERS:-0}" = 1; then
  "$PROVIDER_SCRIPT" --prefix "$prefix"
fi
if test "$use_existing_prefix" = 1; then
  # Reuse the prepared prefix by default. An explicit update is available
  # for callers that need it, but it is followed by provider restaging.
  stop_server
  if test "${VKMT_CEF_WINEBOOT_UPDATE:-0}" = 1; then
    VKMT_PERF_RUN_ID=cef-wineboot VKMT_CEF_WINE_NO_EXPLORER=1 VKMT_CEF_WINEDEBUG=-all \
      run_wine "$run_root/wineboot-update.log" "$(duration_arg "${VKMT_CEF_BOOT_TIMEOUT:-120}")" \
        "$WINEBOOT" --update
    stop_server
    "$VKMT/scripts/vkmt-prefix" sync-wow64 --prefix "$prefix"
    test ! -f "$prefix/.vkmt/dxmt-arm64ec.sha256" ||
      "$VKMT/scripts/vkmt-prefix" sync-dxmt --prefix "$prefix"
  fi
else
  VKMT_PERF_RUN_ID=cef-wineboot VKMT_CEF_WINE_NO_EXPLORER=1 VKMT_CEF_WINEDEBUG=-all \
    run_wine "$run_root/wineboot.log" "$(duration_arg "${VKMT_CEF_BOOT_TIMEOUT:-120}")" \
      "$WINEBOOT" --init
  stop_server
fi
# wineboot can repopulate system32 from the build tree, so restore the pinned
# provider/runtime closure before verifying or executing the guest.
if test "$use_existing_prefix" = 0 || test "${VKMT_CEF_RESTAGE_PROVIDERS:-0}" = 1; then
  "$PROVIDER_SCRIPT" --prefix "$prefix"
fi
"$PROVIDER_SCRIPT" --verify-prefix "$prefix"
if test "$use_existing_prefix" = 1; then
  "$VKMT/scripts/vkmt-prefix" verify --prefix "$prefix"
fi

probe_failures=0

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
      # Prefer the release's SwiftShader pair on Apple Silicon/Wine. The
      # MoltenVK/ANGLE path currently reaches GPU-child startup but can
      # respawn the compositor before CEF creates a renderer. Keep an explicit
      # opt-out for differential diagnostics.
      if test "${VKMT_CEF_BUNDLED_SWIFTSHADER:-1}" = 1; then
        angle_args=(--use-gl=angle --use-angle=swiftshader
                    --enable-unsafe-swiftshader --disable-vulkan)
      else
        angle_args=(--use-gl=angle --use-angle=swiftshader --disable-vulkan)
      fi
      start_url="$https_url"
      ;;
    i386)
      cdp_port=19461
      cdp_transport=browser
      # CEF's bundled 32-bit SwANGLE Vulkan context is not usable over the
      # Wine/MoltenVK boundary.  OSR does not require a GPU compositor, so use
      # Chromium's software paint path and prevent fallback into SwANGLE.
      angle_args=(--use-gl=disabled --disable-gpu --disable-gpu-compositing
                  --disable-gpu-rasterization
                  --disable-vulkan --in-process-gpu
                  --renderer-process-limit=1)
      start_url=data:text/html,VKMT_CEF_I386_OSR
      ;;
  esac
  start_url="${VKMT_CEF_START_URL:-$start_url}"
  extra_args=()
  if test -n "${VKMT_CEF_EXTRA_ARGS:-}"; then
    read -r -a extra_args <<<"$VKMT_CEF_EXTRA_ARGS"
  fi
  if test -n "${VKMT_CEF_HOST_RESOLVER_RULES:-}"; then
    extra_args+=("--host-resolver-rules=$VKMT_CEF_HOST_RESOLVER_RULES")
  fi
  render_args=()
  if test "$render_mode" = osr; then
    render_args=(--off-screen-rendering-enabled --hide-controls)
  fi
  netlog_args=()
  if test "${VKMT_CEF_NETLOG:-0}" = 1; then
    netlog_args=("--log-net-log=$(winpath "$run_root/$arch-netlog.json")"
                 --net-log-capture-mode=Everything)
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
      cefclient.exe)
        continue
        ;;
      chrome_elf.dll)
        test "${VKMT_CEF_USE_BUNDLED_CHROME_ELF:-0}" = 1 || continue
        ;;
      vulkan-1.dll|vk_swiftshader*)
        test "${VKMT_CEF_BUNDLED_SWIFTSHADER:-1}" = 1 || continue
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
  # Run through the compatibility launcher. It starts cefclient_real.exe and
  # injects the child-process hook before CEF creates renderer/utility/GPU
  # children; launching cefclient directly only exercises the browser process.
  ln -s "$release/cefclient.exe" "$client/cefclient_real.exe"
  install -m 0755 "$COMPAT/$arch/cefcompat-wrapper.exe" "$client/cefclient.exe"
  install -m 0644 "$COMPAT/$arch/metalsharp-cefchildhook.dll" \
    "$client/metalsharp-cefchildhook.dll"
  if test "${VKMT_CEF_USE_BUNDLED_CHROME_ELF:-0}" != 1; then
    install -m 0644 "$COMPAT/$arch/chrome_elf.dll" "$client/chrome_elf.dll"
  fi

  find "$prefix/drive_c/users" -type f \
    \( -name metalsharp-cefchildhook.log -o -name metalsharp-chrome-elf-compat.log \) \
    -exec unlink {} \;
  set +e
  software_children="${VKMT_CEF_SOFTWARE_CHILDREN:-0}"
  test "$arch" = i386 && software_children="${VKMT_CEF_SOFTWARE_CHILDREN:-1}"
  export VKMT_CEF_SOFTWARE_CHILDREN="$software_children"
  VKMT_PERF_RUN_ID="cef-$arch" \
  run_wine "$run_root/$arch-client.log" "$(duration_arg "${VKMT_CEF_CLIENT_WINDOW:-90}")" \
    "$client/cefclient.exe" --no-sandbox --disable-gpu-sandbox \
    "${angle_args[@]}" \
    ${extra_args[@]+"${extra_args[@]}"} \
    ${render_args[@]+"${render_args[@]}"} \
    ${netlog_args[@]+"${netlog_args[@]}"} \
    --ignore-certificate-errors --autoplay-policy=no-user-gesture-required \
    "--remote-debugging-port=$cdp_port" \
    "--url=$start_url" \
    "--log-file=$(winpath "$run_root/$arch-cef.log")" &
  client_job=$!
  set -e
  if test "${VKMT_CEF_PRE_GATE_WINDOW:-0}" -gt 0; then
    echo "CEF_${arch_marker}_VISIBLE_PAGE_DWELL_${VKMT_CEF_PRE_GATE_WINDOW}s url=$start_url"
    sleep "${VKMT_CEF_PRE_GATE_WINDOW}"
  fi
  set +e
  gtimeout --signal=TERM --kill-after=10s \
    "$(duration_arg "${VKMT_CEF_CDP_TIMEOUT:-60}")" \
    node "${VKMT_CEF_CDP_PROBE:-$VKMT/test/browser/chromium_cdp_probe.mjs}" "$cdp_port" \
      "$run_root/$arch-screenshot.png" "$https_url" \
      "$cdp_transport" "$start_url" \
      >"$run_root/$arch-cdp.log" 2>&1
  cdp_status=$?
  set -e
  if test "$cdp_status" -eq 0 &&
     test "${VKMT_CEF_POST_GATE_WINDOW:-0}" -gt 0; then
    render_marker="$(printf '%s' "$render_mode" | tr '[:lower:]' '[:upper:]')"
    echo "CEF_${arch_marker}_${render_marker}_VISIBLE_OBSERVATION_${VKMT_CEF_POST_GATE_WINDOW}s"
    sleep "${VKMT_CEF_POST_GATE_WINDOW}"
  fi
  kill "$client_job" 2>/dev/null || true
  stop_server
  set +e
  wait "$client_job" 2>/dev/null
  client_status=$?
  set -e

  arch_status=0
  trace_count="$(find "$trace_dir" -type f -name "vkmt-perf-cef-$arch-*.tsv" -print | wc -l | tr -d ' ')"
  if test "$trace_count" -gt 0; then
    echo "CEF_${arch_marker}_FEX_ALLOCATION_TRACE_OK files=$trace_count"
  else
    echo "CEF_${arch_marker}_FEX_ALLOCATION_TRACE_MISSING"
    arch_status=1
  fi
  if test "$cdp_status" -ne 0; then
    echo "CEF_${arch_marker}_CDP_DIAGNOSTIC_FAIL status=$cdp_status"
    arch_status=1
  fi
  for marker in CHROMIUM_CDP_NAVIGATION_OK CHROMIUM_CDP_HTTPS_AUDIO_OK \
                CHROMIUM_CDP_INPUT_OK; do
    if ! grep -q "$marker" "$run_root/$arch-cdp.log"; then
      echo "CEF_${arch_marker}_MISSING_$marker"
      arch_status=1
    fi
  done
  if ! grep -q 'CHROMIUM_CDP_PIXEL_OK .* 17,34,51,255' \
      "$run_root/$arch-cdp.log"; then
    echo "CEF_${arch_marker}_MISSING_PIXEL_MARKER"
    arch_status=1
  fi
  if ! test -s "$run_root/$arch-screenshot.png"; then
    echo "CEF_${arch_marker}_MISSING_SCREENSHOT"
    arch_status=1
  fi
  if test "${VKMT_CDP_SKIP_PAGE_CAPTURE:-0}" != 1 &&
     ! test -s "$run_root/$arch-screenshot-page.png"; then
    echo "CEF_${arch_marker}_MISSING_PAGE_SCREENSHOT"
    arch_status=1
  fi

  child_log="$(prefix_log metalsharp-cefchildhook.log)"
  if test "${VKMT_CEF_DISABLE_CHILD_HOOK:-0}" = 1 &&
     test "${VKMT_CEF_SKIP_CHILD_HOOK_ASSERT:-0}" = 1; then
    echo "CEF_${arch_marker}_SUBPROCESS_TRACE_SKIPPED"
  elif test -f "$child_log"; then
    cp -p "$child_log" "$run_root/$arch-cefchildhook.log"
    if grep -Eq -- 'CreateProcessW CEF child: .*--type=(renderer|utility|gpu-process)' \
        "$child_log"; then
      echo "CEF_${arch_marker}_SUBPROCESS_TRACE_OK"
    else
      echo "CEF_${arch_marker}_SUBPROCESS_TRACE_MISSING"
      arch_status=1
    fi
    if grep -Eq -- 'CreateProcessW CEF child: .*--type=renderer' "$child_log"; then
      echo "CEF_${arch_marker}_RENDERER_TRACE_OK"
    else
      echo "CEF_${arch_marker}_RENDERER_TRACE_MISSING"
      arch_status=1
    fi
  else
    echo "CEF_${arch_marker}_MISSING_CHILD_HOOK_LOG"
    arch_status=1
  fi

  if test "${VKMT_CEF_USE_BUNDLED_CHROME_ELF:-0}" != 1; then
    elf_log="$(prefix_log metalsharp-chrome-elf-compat.log)"
    if ! test -f "$elf_log"; then
      echo "CEF_${arch_marker}_MISSING_CHROME_ELF_LOG"
      arch_status=1
    else
      if ! grep -q 'chrome_elf compatibility DLL loaded' "$elf_log"; then
        echo "CEF_${arch_marker}_MISSING_CHROME_ELF_LOAD"
        arch_status=1
      fi
      cp -p "$elf_log" "$run_root/$arch-chrome-elf.log"
    fi
  fi
  if ! test -f "$run_root/$arch-cef.log" || ! test -s "$run_root/$arch-cef.log"; then
    echo "CEF_${arch_marker}_MISSING_CEF_LOG"
    arch_status=1
  fi
  case "$client_status" in
    0|124|143) ;;
    *)
      # Wine may deliver the observation-window TERM to the PE child and
      # return that child's code. Runtime evidence above is authoritative.
      echo "CEF_${arch_marker}_OBSERVATION_EXIT_$client_status"
      ;;
  esac
  if test "$arch_status" -eq 0; then
    echo "CEF_${arch_marker}_SUBPROCESS_RUNTIME_OK"
    if test "$render_mode" = windowed; then
      echo "CEF_${arch_marker}_WINDOWED_HTTPS_INPUT_AUDIO_PIXEL_OK"
    else
      echo "CEF_${arch_marker}_OSR_HTTPS_INPUT_AUDIO_PIXEL_OK"
    fi
  else
    echo "CEF_${arch_marker}_DIAGNOSTIC_COMPLETE"
    probe_failures=1
  fi
done

if test "$probe_failures" -eq 0; then
  echo CEF_X64_I386_ALL_OK
else
  echo CEF_X64_I386_DIAGNOSTIC_COMPLETE
fi
exit "$probe_failures"
