#!/bin/bash
# Launch the user-facing VKMT CEF browser. Unlike cefclient, this executable
# owns BrowserHost creation and calls CreateBrowser with the requested URL.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${VKMT_WINE_BUILD:-$VKMT/wine/build-ec}"
VERSION='109.1.18+gf1c41e4+chromium-109.0.5414.120'
TOOLCHAIN="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal"
RELEASE="$VKMT/third_party/cef-$VERSION/windows64/Release"
COMPAT="$VKMT/build/cef-compat/x86_64"
PRODUCT="$VKMT/build/vkmt-cef-browser/x86_64"
RUNTIME="${VKMT_BROWSER_RUNTIME:-$VKMT/build/vkmt-browser-runtime/x86_64}"
PREFIX="${VKMT_BROWSER_PREFIX:-$VKMT/build/vkmt-browser-prefix}"
URL="${VKMT_BROWSER_URL:-https://example.com/}"
LOG_DIR="${VKMT_BROWSER_LOG_DIR:-$PREFIX/.vkmt/browser}"
USE_EXISTING_PREFIX=0

if test -n "${VKMT_BROWSER_PREFIX:-}"; then
  case "$PREFIX" in /*) ;; *) echo "VKMT_BROWSER_PREFIX must be absolute" >&2; exit 2 ;; esac
  test -f "$PREFIX/.vkmt/receipt.json" || {
    echo "VKMT_BROWSER_PREFIX is not a receipt-backed VKMT prefix: $PREFIX" >&2
    exit 1
  }
  USE_EXISTING_PREFIX=1
fi

test -x "$BUILD/wine" && test -x "$BUILD/server/wineserver"
test -f "$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
test -f "$RELEASE/libcef.dll"
test -f "$PRODUCT/vkmt-browser.exe" || "$VKMT/scripts/build-vkmt-cef-browser.sh"
# Runtime launch must not rebuild the two-ABI compatibility closure. Build it
# only when the required product DLL is absent; explicit compatibility changes
# remain rebuilt through build-metalsharp-cef-compat.sh.
test -f "$COMPAT/chrome_elf.dll" || "$VKMT/scripts/build-metalsharp-cef-compat.sh" >/dev/null

mkdir -p "$RUNTIME" "$PREFIX/drive_c/windows/system32" \
         "$PREFIX/drive_c/windows/syswow64" "$LOG_DIR"
for item in "$RELEASE"/*; do
  name="$(basename "$item")"
  case "$name" in cefclient.exe|chrome_elf.dll) continue ;; esac
  test -e "$RUNTIME/$name" || ln -s "$item" "$RUNTIME/$name"
done
install -m 0755 "$PRODUCT/vkmt-browser.exe" "$RUNTIME/vkmt-browser.exe"
install -m 0644 "$COMPAT/chrome_elf.dll" "$RUNTIME/chrome_elf.dll"
for dll in libc++.dll libunwind.dll; do
  install -m 0644 "$TOOLCHAIN/x86_64-w64-mingw32/bin/$dll" "$RUNTIME/$dll"
done

# Populate a disposable browser prefix once. A receipt-backed prefix supplied
# by VKMT_BROWSER_PREFIX is authoritative: do not recreate it or run wineboot;
# this is the path used by the canonical CEF/Electron probes.
if test "$USE_EXISTING_PREFIX" = 0 &&
   test ! -f "$PREFIX/.vkmt/browser-initialized"; then
  for dll in xtajit64 xtajit wow64 wow64win; do
    install -m 0644 "$BUILD/dlls/$dll/aarch64-windows/$dll.dll" \
      "$PREFIX/drive_c/windows/system32/$dll.dll"
  done
  while IFS= read -r dll; do
    install -m 0644 "$dll" "$PREFIX/drive_c/windows/syswow64/$(basename "$dll")"
  done < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)
  export WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" VKMT_RUNTIME_ROOT="$VKMT"
  "$VKMT/scripts/stage-runtime-providers.sh" --prefix "$PREFIX"
  . "$VKMT/scripts/vkmt-runtime-env.sh"
  WINEDEBUG=-all "$BUILD/wine" \
    "$BUILD/programs/wineboot/aarch64-windows/wineboot.exe" --init \
    >"$LOG_DIR/wineboot.log" 2>&1
  "$VKMT/scripts/stage-runtime-providers.sh" --prefix "$PREFIX"
  "$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$PREFIX"
  : >"$PREFIX/.vkmt/browser-initialized"
fi

export WINEPREFIX="$PREFIX" WINEBUILDDIR="$BUILD" VKMT_RUNTIME_ROOT="$VKMT"
if test -n "${VKMT_BROWSER_XTAJIT64_SOURCE:-}"; then
  export VKMT_XTAJIT64_SOURCE="$VKMT_BROWSER_XTAJIT64_SOURCE"
  export VKMT_XTAJIT64_SHA256="${VKMT_BROWSER_XTAJIT64_SHA256:?set the candidate SHA-256}"
fi
if test "$USE_EXISTING_PREFIX" = 1; then
  "$VKMT/scripts/vkmt-prefix" sync-wow64 --prefix "$PREFIX"
  "$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$PREFIX"
  if test "${VKMT_BROWSER_SKIP_PREFIX_VERIFY:-0}" != 1; then
    "$VKMT/scripts/vkmt-prefix" verify --prefix "$PREFIX"
  fi
else
  "$VKMT/scripts/stage-runtime-providers.sh" --prefix "$PREFIX"
  "$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$PREFIX"
fi
. "$VKMT/scripts/vkmt-runtime-env.sh"
log="$LOG_DIR/browser-$(date +%Y%m%dT%H%M%S).log"
cef_log="$LOG_DIR/cef-$(date +%Y%m%dT%H%M%S).log"
browser_log_win="Z:${log//\//\\}"
debug_args=()
if test -n "${VKMT_BROWSER_REMOTE_DEBUG_PORT:-}"; then
  debug_args+=("--remote-debugging-port=$VKMT_BROWSER_REMOTE_DEBUG_PORT")
fi
extra_args=()
if test -n "${VKMT_BROWSER_EXTRA_ARGS:-}"; then
  read -r -a extra_args <<<"$VKMT_BROWSER_EXTRA_ARGS"
fi
echo "VKMT_BROWSER_LAUNCH url=$URL runtime=$RUNTIME prefix=$PREFIX log=$log"
launch_args=(
  --no-sandbox
  --use-gl=angle --use-angle=swiftshader --enable-unsafe-swiftshader
  --disable-vulkan --ignore-certificate-errors
  "--url=$URL" "--vkmt-browser-log=$browser_log_win" "--log-file=Z:${cef_log//\//\\}"
)
if test "${#debug_args[@]}" -gt 0; then
  launch_args+=("${debug_args[@]}")
fi
if test "${#extra_args[@]}" -gt 0; then
  launch_args+=("${extra_args[@]}")
fi
wine_env=(
  WINEDEBUG="${VKMT_BROWSER_WINEDEBUG:--all}"
  WINEDLLOVERRIDES="${VKMT_BROWSER_WINEDLLOVERRIDES:-vulkan-1=n,b}"
  FEX_TSOENABLED=0
  FEX_VECTORTSOENABLED=0
  FEX_MEMCPYSETTSOENABLED=0
)

if test "${VKMT_BROWSER_WAIT_FOR_RENDER:-0}" = 1; then
  case "${VKMT_BROWSER_RENDER_TIMEOUT:-60}" in
    ''|*[!0-9]*) echo "VKMT_BROWSER_RENDER_TIMEOUT must be integer seconds" >&2; exit 2 ;;
  esac
  driver_log="$LOG_DIR/driver-$(date +%Y%m%dT%H%M%S).log"
  env "${wine_env[@]}" "$BUILD/wine" "$RUNTIME/vkmt-browser.exe" "${launch_args[@]}" \
    >"$driver_log" 2>&1 &
  browser_pid=$!
  remaining="${VKMT_BROWSER_RENDER_TIMEOUT:-60}"
  rendered=0
  while test "$remaining" -gt 0; do
    # The Windows host writes CRLF records. Match the marker token rather
    # than anchoring on LF so the probe is portable across host grep builds.
    if grep -q 'VKMT_BROWSER_PIXEL_OK' "$log" 2>/dev/null; then
      rendered=1
      break
    fi
    if ! kill -0 "$browser_pid" 2>/dev/null; then break; fi
    sleep 1
    remaining=$((remaining - 1))
  done
  if test "$rendered" = 1; then
    WINEPREFIX="$PREFIX" "$BUILD/server/wineserver" -k 2>/dev/null || true
    WINEPREFIX="$PREFIX" "$BUILD/server/wineserver" -w 2>/dev/null || true
    set +e
    wait "$browser_pid"
    set -e
    echo "VKMT_BROWSER_RENDER_OK log=$log driver=$driver_log"
    exit 0
  fi
  kill "$browser_pid" 2>/dev/null || true
  WINEPREFIX="$PREFIX" "$BUILD/server/wineserver" -k 2>/dev/null || true
  WINEPREFIX="$PREFIX" "$BUILD/server/wineserver" -w 2>/dev/null || true
  echo "VKMT_BROWSER_RENDER_MISSING log=$log driver=$driver_log" >&2
  exit 1
fi

exec env "${wine_env[@]}" "$BUILD/wine" "$RUNTIME/vkmt-browser.exe" "${launch_args[@]}"
