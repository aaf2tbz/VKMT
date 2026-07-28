#!/bin/bash
# Prove i386 opengl32/WGL execution over the native ARM64 Wine/macOS driver.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
LLVM_MINGW="${LLVM_MINGW:-$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal}"
WINE_BUILD="$VKMT/wine/build-ec"
PROBE_SOURCE="$VKMT/test/opengl_runtime.c"
PROBE_EXE="$VKMT/test/opengl_runtime_i386.exe"
XTAJIT="$WINE_BUILD/dlls/xtajit/aarch64-windows/xtajit.dll"
WOW64="$WINE_BUILD/dlls/wow64/aarch64-windows/wow64.dll"
WOW64WIN="$WINE_BUILD/dlls/wow64win/aarch64-windows/wow64win.dll"
WINEBOOT="$WINE_BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
WINEMAC="$WINE_BUILD/dlls/winemac.drv/i386-windows/winemac.drv"

export PATH="$LLVM_MINGW/bin:$PATH"
i686-w64-mingw32-clang -O2 -g -Wall -Wextra "$PROBE_SOURCE" -o "$PROBE_EXE" -luser32 -lgdi32

for file in "$WINE_BUILD/wine" "$WINE_BUILD/server/wineserver" "$XTAJIT" "$WOW64" \
            "$WOW64WIN" "$WINEBOOT" "$WINEMAC" "$PROBE_EXE"; do
  test -e "$file" || { echo "Missing OpenGL probe dependency: $file" >&2; exit 1; }
done
test "$("$LLVM_MINGW/bin/llvm-readobj" --file-headers "$PROBE_EXE" |
       awk '/Machine:/ {print $2; exit}')" = IMAGE_FILE_MACHINE_I386

RUNS_DIR="$VKMT/build/probe-runs"
mkdir -p "$RUNS_DIR"
run_root="$(mktemp -d "$RUNS_DIR/opengl-i386.XXXXXX")"
prefix="$run_root/prefix"
marker="$run_root/opengl-markers"
bootstrap_log="$run_root/bootstrap.log"
probe_log="$run_root/opengl.log"
wine_pid=""
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=10s "${VKMT_OPENGL_TIMEOUT:-120}s")
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=10s "${VKMT_OPENGL_TIMEOUT:-120}s")
fi

cleanup() {
  status=$?
  [[ -z "$wine_pid" ]] || kill -TERM "$wine_pid" 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINE_BUILD/server/wineserver" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINE_BUILD/server/wineserver" -w 2>/dev/null || true
  case "$run_root" in
    "$RUNS_DIR"/*)
      if [[ "${VKMT_KEEP_PROBE_RUN:-0}" = 1 ]]; then
        echo "Retained disposable OpenGL run: $run_root" >&2
      else
        /usr/bin/trash "$run_root" 2>/dev/null || true
      fi
      ;;
  esac
  exit "$status"
}
trap cleanup EXIT

system32="$prefix/drive_c/windows/system32"
syswow64="$prefix/drive_c/windows/syswow64"
mkdir -p "$system32" "$syswow64"
install -m 0644 "$XTAJIT" "$system32/xtajit.dll"
install -m 0644 "$WOW64" "$system32/wow64.dll"
install -m 0644 "$WOW64WIN" "$system32/wow64win.dll"
while IFS= read -r dll; do
  install -m 0644 "$dll" "$syswow64/$(basename "$dll")"
done < <(find "$WINE_BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)
install -m 0644 "$WINEMAC" "$syswow64/winemac.drv"

run_wine() {
  local output=$1
  local no_explorer=$2
  shift 2
  env_args=(WINEPREFIX="$prefix" WINEBUILDDIR="$WINE_BUILD" WINEBOOTSTRAPMODE=1
            WINEDEBUG="${VKMT_OPENGL_WINEDEBUG:--all}")
  [[ "$no_explorer" != 1 ]] || env_args+=(WINE_NO_EXPLORER=1)
  "${timeout_cmd[@]}" env "${env_args[@]}" "$WINE_BUILD/wine" "$@" >"$output" 2>&1 &
  wine_pid=$!
  if wait "$wine_pid"; then run_code=0; else run_code=$?; fi
  wine_pid=""
  return "$run_code"
}

if ! run_wine "$bootstrap_log" 1 "$WINEBOOT" --init; then
  echo "OpenGL native ARM64 wineboot failed" >&2
  tail -n 120 "$bootstrap_log" >&2
  exit 1
fi
# The bootstrap server deliberately has no explorer.  End that session before
# the interactive probe so only one process can publish and own the desktop.
WINEPREFIX="$prefix" "$WINE_BUILD/server/wineserver" -k
WINEPREFIX="$prefix" "$WINE_BUILD/server/wineserver" -w

if run_wine "$probe_log" 0 "$PROBE_EXE" "Z:$marker"; then code=0; else code=$?; fi
if [[ "$code" -ne 0 ]] || [[ ! -f "$marker" ]] ||
   ! rg -F 'OPENGL_RUNTIME_ALL_OK' "$marker" >/dev/null; then
  install -m 0644 "$probe_log" "$VKMT/build/opengl-i386-probe.latest.log"
  [[ ! -f "$marker" ]] ||
    install -m 0644 "$marker" "$VKMT/build/opengl-i386-probe.latest.markers"
  echo "i386 OpenGL runtime probe failed with exit $code" >&2
  [[ ! -f "$marker" ]] || sed -n '1,120p' "$marker" >&2
  tail -n 160 "$probe_log" >&2
  exit 1
fi

echo "i386 OpenGL runtime passed"
sed -n '1,120p' "$marker"
