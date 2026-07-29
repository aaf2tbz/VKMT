#!/bin/bash
# Prove XInput and DirectInput in one prefix across every supported guest mode.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
RUNS="$VKMT/build/probe-runs"
SOURCE="$VKMT/test/input_runtime_probe.c"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
XTAJIT64="$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll"
XTAJIT="$BUILD/dlls/xtajit/aarch64-windows/xtajit.dll"
WOW64="$BUILD/dlls/wow64/aarch64-windows/wow64.dll"
WOW64WIN="$BUILD/dlls/wow64win/aarch64-windows/wow64win.dll"
WINEBUS="$BUILD/dlls/winebus.sys/winebus.so"
NATIVE_SDL2="$BUILD/dlls/ntdll/libSDL2-2.0.0.dylib"

for required in "$SOURCE" "$WINE" "$WINESERVER" "$WINEBOOT" "$XTAJIT64" \
    "$XTAJIT" "$WOW64" "$WOW64WIN" "$WINEBUS" "$NATIVE_SDL2"; do
  test -e "$required" || { echo "Missing input-runtime artifact: $required" >&2; exit 1; }
done
for macho in "$WINE" "$WINESERVER" "$WINEBUS" "$NATIVE_SDL2"; do
  test "$(/usr/bin/lipo -archs "$macho")" = arm64 || {
    echo "Non-ARM64 host artifact: $macho" >&2
    exit 1
  }
done
if translated="$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null)"; then
  test "$translated" = 0 || { echo "Input runner is under Rosetta" >&2; exit 1; }
fi

mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/input-runtime.XXXXXX")"
prefix="$run_root/prefix"
wine_pid=""
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=10s "${VKMT_INPUT_TIMEOUT:-120}s")
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=10s "${VKMT_INPUT_TIMEOUT:-120}s")
fi

cleanup()
{
  status=$?
  test -z "$wine_pid" || kill -TERM "$wine_pid" 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  case "$run_root" in
    "$RUNS"/*)
      if test "${VKMT_KEEP_PROBE_RUN:-0}" = 1; then
        echo "Retained disposable input run: $run_root" >&2
      else
        /usr/bin/trash "$run_root" 2>/dev/null || true
      fi
      ;;
  esac
  exit "$status"
}
trap cleanup EXIT

stop_server()
{
  test "${VKMT_INPUT_SKIP_STOPS:-0}" != 1 || return 0
  WINEPREFIX="$prefix" "$WINESERVER" -k
  WINEPREFIX="$prefix" "$WINESERVER" -w
}

run_wine()
{
  output=$1
  shift
  "${timeout_cmd[@]}" env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" \
    WINEBOOTSTRAPMODE=1 WINE_NO_EXPLORER=1 WINEDEBUG="${VKMT_INPUT_WINEDEBUG:--all}" \
    "$WINE" "$@" >"$output" 2>&1 &
  wine_pid=$!
  if wait "$wine_pid"; then code=0; else code=$?; fi
  wine_pid=""
  return "$code"
}

compile()
{
  compiler=$1
  output=$2
  shift 2
  "$TOOL/$compiler" -O2 -g -Wall -Wextra "$@" "$SOURCE" -o "$output" \
    -ldxguid -lole32
}
compile aarch64-w64-mingw32-clang "$run_root/arm64.exe" -ffixed-x18 -ffixed-x28
compile arm64ec-w64-mingw32-clang "$run_root/arm64ec.exe" -ffixed-x18 -ffixed-x28
compile x86_64-w64-mingw32-clang "$run_root/x86_64.exe" -fno-vectorize -fno-slp-vectorize
compile i686-w64-mingw32-clang "$run_root/i386.exe"

system32="$prefix/drive_c/windows/system32"
syswow64="$prefix/drive_c/windows/syswow64"
mkdir -p "$system32" "$syswow64"
install -m 0644 "$XTAJIT64" "$system32/xtajit64.dll"
install -m 0644 "$XTAJIT" "$system32/xtajit.dll"
install -m 0644 "$WOW64" "$system32/wow64.dll"
install -m 0644 "$WOW64WIN" "$system32/wow64win.dll"
while IFS= read -r dll; do
  install -m 0644 "$dll" "$syswow64/$(basename "$dll")"
done < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)

echo "INPUT_WINEBOOT_BEGIN"
"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
run_wine "$run_root/wineboot.log" "$WINEBOOT" --init || {
  echo "Input-runtime wineboot failed" >&2
  tail -n 160 "$run_root/wineboot.log" >&2
  exit 1
}
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"
echo "INPUT_WINEBOOT_OK"
stop_server

# SDL supplies normalized controller mappings and haptics on macOS.  Disable
# the parallel raw IOHID joystick provider so one physical pad is not exposed
# twice with an unnormalized HID descriptor.
run_wine "$run_root/winebus-registry.log" reg.exe add \
  'HKLM\System\CurrentControlSet\Services\WineBus' \
  /v DisableHidraw /t REG_DWORD /d 1 /f
stop_server

for arch in ${VKMT_INPUT_ARCHES:-arm64 arm64ec x86_64 i386}; do
  log="$run_root/$arch.log"
  if ! run_wine "$log" "$run_root/$arch.exe"; then
    install -m 0644 "$log" "$VKMT/build/input-runtime.latest.log"
    echo "$arch input-runtime probe failed" >&2
    tail -n 200 "$log" >&2
    exit 1
  fi
  grep -q INPUT_RUNTIME_ALL_OK "$log" || {
    install -m 0644 "$log" "$VKMT/build/input-runtime.latest.log"
    echo "$arch input-runtime success marker missing" >&2
    tail -n 200 "$log" >&2
    exit 1
  }
  arch_upper="$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')"
  echo "INPUT_${arch_upper}_XINPUT_DINPUT_OK"
  grep -E 'INPUT_(ATTACHED_CONTROLLER_BEHAVIOR_OK|NO_CONTROLLER_ATTACHED)' "$log"
  stop_server
done
echo INPUT_SINGLE_PREFIX_ALL_ARCHITECTURES_OK
