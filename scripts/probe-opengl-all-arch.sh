#!/bin/bash
# Prove one OpenGL/WGL runtime in one prefix across ARM64, ARM64EC, x86_64, and i386.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
RUNS="$VKMT/build/probe-runs"
SOURCE="$VKMT/test/opengl_runtime.c"
SHADER_SOURCE="$VKMT/test/opengl_runtime_probe.c"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
XTAJIT64="$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll"
XTAJIT="$BUILD/dlls/xtajit/aarch64-windows/xtajit.dll"
WOW64="$BUILD/dlls/wow64/aarch64-windows/wow64.dll"
WOW64WIN="$BUILD/dlls/wow64win/aarch64-windows/wow64win.dll"
WINEMAC32="$BUILD/dlls/winemac.drv/i386-windows/winemac.drv"

for required in "$WINE" "$WINESERVER" "$WINEBOOT" "$XTAJIT64" "$XTAJIT" \
    "$WOW64" "$WOW64WIN" "$WINEMAC32" "$SOURCE" "$SHADER_SOURCE"; do
  test -e "$required" || { echo "Missing all-architecture OpenGL input: $required" >&2; exit 1; }
done
for macho in "$WINE" "$WINESERVER" "$BUILD/dlls/opengl32/opengl32.so"; do
  test "$(/usr/bin/lipo -archs "$macho")" = arm64 || {
    echo "Non-ARM64 OpenGL host artifact: $macho" >&2
    exit 1
  }
done
if translated="$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null)"; then
  test "$translated" = 0 || { echo "OpenGL runner is under Rosetta" >&2; exit 1; }
fi

mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/opengl-all-arch.XXXXXX")"
prefix="$run_root/prefix"
wine_pid=""
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=10s "${VKMT_OPENGL_TIMEOUT:-120}s")
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=10s "${VKMT_OPENGL_TIMEOUT:-120}s")
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
        echo "Retained disposable OpenGL run: $run_root" >&2
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
  WINEPREFIX="$prefix" "$WINESERVER" -k
  WINEPREFIX="$prefix" "$WINESERVER" -w
}

run_wine()
{
  output=$1
  no_explorer=$2
  shift 2
  env_args=(WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1
            WINEDEBUG="${VKMT_OPENGL_WINEDEBUG:--all}")
  test "$no_explorer" != 1 || env_args+=(WINE_NO_EXPLORER=1)
  "${timeout_cmd[@]}" env "${env_args[@]}" "$WINE" "$@" >"$output" 2>&1 &
  wine_pid=$!
  if wait "$wine_pid"; then code=0; else code=$?; fi
  wine_pid=""
  return "$code"
}

"$TOOL/aarch64-w64-mingw32-clang" -O2 -g -Wall -Wextra -ffixed-x18 -ffixed-x28 \
  "$SOURCE" -o "$run_root/arm64.exe" -luser32 -lgdi32
"$TOOL/aarch64-w64-mingw32-clang" -O2 -g -Wall -Wextra -ffixed-x18 -ffixed-x28 \
  "$SHADER_SOURCE" -o "$run_root/arm64_shader.exe" -lopengl32 -luser32 -lgdi32
"$TOOL/arm64ec-w64-mingw32-clang" -O2 -g -Wall -Wextra -ffixed-x18 -ffixed-x28 \
  "$SOURCE" -o "$run_root/arm64ec.exe" -luser32 -lgdi32
"$TOOL/arm64ec-w64-mingw32-clang" -O2 -g -Wall -Wextra -ffixed-x18 -ffixed-x28 \
  "$SHADER_SOURCE" -o "$run_root/arm64ec_shader.exe" -lopengl32 -luser32 -lgdi32
"$TOOL/x86_64-w64-mingw32-clang" -O2 -g -Wall -Wextra -fno-vectorize -fno-slp-vectorize \
  "$SOURCE" -o "$run_root/x86_64.exe" -luser32 -lgdi32
"$TOOL/x86_64-w64-mingw32-clang" -O2 -g -Wall -Wextra -fno-vectorize -fno-slp-vectorize \
  "$SHADER_SOURCE" -o "$run_root/x86_64_shader.exe" -lopengl32 -luser32 -lgdi32
"$TOOL/i686-w64-mingw32-clang" -O2 -g -Wall -Wextra \
  "$SOURCE" -o "$run_root/i386.exe" -luser32 -lgdi32
"$TOOL/i686-w64-mingw32-clang" -O2 -g -Wall -Wextra \
  "$SHADER_SOURCE" -o "$run_root/i386_shader.exe" -lopengl32 -luser32 -lgdi32

for spec in \
    "arm64.exe:IMAGE_FILE_MACHINE_ARM64" \
    "arm64ec.exe:IMAGE_FILE_MACHINE_ARM64EC" \
    "x86_64.exe:IMAGE_FILE_MACHINE_AMD64" \
    "i386.exe:IMAGE_FILE_MACHINE_I386"; do
  file=${spec%%:*}
  expected=${spec#*:}
  machine="$("$TOOL/llvm-readobj" --file-headers "$run_root/$file" |
    awk '/Machine:/ {print $2; exit}')"
  test "$machine" = "$expected" || {
    echo "Wrong OpenGL fixture architecture: $file ($machine, expected $expected)" >&2
    exit 1
  }
done

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
install -m 0644 "$WINEMAC32" "$syswow64/winemac.drv"

run_wine "$run_root/wineboot.log" 1 "$WINEBOOT" --init || {
  echo "All-architecture OpenGL wineboot failed" >&2
  tail -n 120 "$run_root/wineboot.log" >&2
  exit 1
}
stop_server

for arch in ${VKMT_OPENGL_ARCHES:-arm64 arm64ec x86_64 i386}; do
  marker="$run_root/$arch.markers"
  if ! run_wine "$run_root/$arch.log" 0 "$run_root/$arch.exe" "Z:$marker"; then
    install -m 0644 "$run_root/$arch.log" "$VKMT/build/opengl-all-arch.latest.log"
    test ! -f "$marker" ||
      install -m 0644 "$marker" "$VKMT/build/opengl-all-arch.latest.markers"
    echo "$arch OpenGL runtime failed" >&2
    test ! -f "$marker" || sed -n '1,120p' "$marker" >&2
    tail -n 120 "$run_root/$arch.log" >&2
    exit 1
  fi
  grep -q 'OPENGL_RUNTIME_ALL_OK' "$marker" || {
    echo "$arch OpenGL success marker missing" >&2
    sed -n '1,120p' "$marker" >&2
    exit 1
  }
  arch_upper="$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')"
  echo "OPENGL_${arch_upper}_RUNTIME_OK"
  stop_server
  if ! run_wine "$run_root/${arch}_shader.log" 0 "$run_root/${arch}_shader.exe"; then
    install -m 0644 "$run_root/${arch}_shader.log" "$VKMT/build/opengl-all-arch.latest.log"
    echo "$arch GLSL runtime failed" >&2
    tail -n 120 "$run_root/${arch}_shader.log" >&2
    exit 1
  fi
  grep -q 'PASS OpenGL runtime probe' "$run_root/${arch}_shader.log" || {
    install -m 0644 "$run_root/${arch}_shader.log" "$VKMT/build/opengl-all-arch.latest.log"
    echo "$arch GLSL runtime success marker missing" >&2
    tail -n 120 "$run_root/${arch}_shader.log" >&2
    exit 1
  }
  echo "OPENGL_${arch_upper}_GLSL120_DRAW_OK"
  stop_server
done

echo OPENGL_SINGLE_PREFIX_ALL_ARCHITECTURES_OK
