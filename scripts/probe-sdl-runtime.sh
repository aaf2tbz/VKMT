#!/bin/bash
# Prove SDL2 and SDL3 on all VKMT guest ABIs in one disposable prefix.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
SDL="$BUILD/sdl-runtime"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
RUNS="$VKMT/build/probe-runs"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
XTAJIT64="$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll"
XTAJIT="$BUILD/dlls/xtajit/aarch64-windows/xtajit.dll"
WOW64="$BUILD/dlls/wow64/aarch64-windows/wow64.dll"
WOW64WIN="$BUILD/dlls/wow64win/aarch64-windows/wow64win.dll"

for required in "$WINE" "$WINESERVER" "$WINEBOOT" "$XTAJIT64" "$XTAJIT" \
    "$WOW64" "$WOW64WIN" "$VKMT/test/sdl2_runtime_probe.c" \
    "$VKMT/test/sdl3_runtime_probe.c" "$VKMT/test/x64emu/movnt_x64.c" \
    "$SDL/manifest.txt"; do
  test -e "$required" || { echo "Missing SDL probe input: $required" >&2; exit 1; }
done
for arch in aarch64 arm64ec x86_64 i386; do
  for file in SDL2.dll SDL3.dll libSDL2.dll.a libSDL3.dll.a; do
    test -f "$SDL/$arch/$file" || {
      echo "Missing SDL $arch artifact: $file" >&2
      exit 1
    }
  done
done

for macho in "$WINE" "$WINESERVER" "$BUILD/dlls/ntdll/ntdll.so"; do
  test "$(/usr/bin/lipo -archs "$macho")" = arm64 || {
    echo "Non-ARM64 host artifact: $macho" >&2
    exit 1
  }
done
if translated="$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null)"; then
  test "$translated" = 0 || { echo "SDL runner is under Rosetta" >&2; exit 1; }
fi

check_machine()
{
  file=$1
  expected=$2
  machine="$("$TOOL/llvm-readobj" --file-headers "$file" |
    awk '/Machine:/ {print $2; exit}')"
  test "$machine" = "$expected" || {
    echo "Wrong PE architecture: $file ($machine, expected $expected)" >&2
    exit 1
  }
}
for family in SDL2 SDL3; do
  check_machine "$SDL/aarch64/$family.dll" IMAGE_FILE_MACHINE_ARM64
  check_machine "$SDL/arm64ec/$family.dll" IMAGE_FILE_MACHINE_ARM64EC
  check_machine "$SDL/x86_64/$family.dll" IMAGE_FILE_MACHINE_AMD64
  check_machine "$SDL/i386/$family.dll" IMAGE_FILE_MACHINE_I386
done

mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/sdl-runtime.XXXXXX")"
prefix="$run_root/prefix"
wine_pid=""
run_succeeded=0
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=10s "${VKMT_SDL_TIMEOUT:-180}s")
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=10s "${VKMT_SDL_TIMEOUT:-180}s")
fi

cleanup()
{
  status=$?
  test -z "$wine_pid" || kill -TERM "$wine_pid" 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  case "$run_root" in
    "$RUNS"/*)
      if test "$run_succeeded" = 1 && test "${VKMT_KEEP_SDL_RUN:-0}" = 1; then
        echo "Retained successful disposable SDL run: $run_root" >&2
      else
        /usr/bin/trash "$run_root" 2>/dev/null || true
      fi
      ;;
  esac
  exit "$status"
}
trap cleanup EXIT

run_wine()
{
  output=$1
  shift
  "${timeout_cmd[@]}" env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" \
    WINEBOOTSTRAPMODE=1 WINE_NO_EXPLORER=1 \
    WINEDEBUG="${VKMT_SDL_WINEDEBUG:--all}" \
    SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
    "$WINE" "$@" >"$output" 2>&1 &
  wine_pid=$!
  if wait "$wine_pid"; then code=0; else code=$?; fi
  wine_pid=""
  return "$code"
}

build_fixture()
{
  arch=$1
  compiler=$2
  sdl_arch=$3
  cflags=(-DVKMT_SDL_RUNTIME_PROBE=1)
  case "$arch" in
    aarch64) cflags+=(-ffixed-x18 -ffixed-x28) ;;
    arm64ec)
      cflags+=(-ffixed-x18 -ffixed-x28 -DSDL_DISABLE_IMMINTRIN_H
        -DSDL_DISABLE_MMINTRIN_H -DSDL_DISABLE_XMMINTRIN_H
        -DSDL_DISABLE_EMMINTRIN_H -DSDL_DISABLE_PMMINTRIN_H)
      ;;
  esac
  mkdir -p "$run_root/$arch"
  "$TOOL/$compiler" -O2 "${cflags[@]}" \
    -I"$SDL/include/SDL2" "$VKMT/test/sdl2_runtime_probe.c" \
    "$SDL/$sdl_arch/libSDL2.dll.a" -o "$run_root/$arch/sdl2_probe.exe"
  "$TOOL/$compiler" -O2 "${cflags[@]}" \
    -I"$SDL/include/SDL3" "$VKMT/test/sdl3_runtime_probe.c" \
    "$SDL/$sdl_arch/libSDL3.dll.a" -o "$run_root/$arch/sdl3_probe.exe"
  install -m 0644 "$SDL/$sdl_arch/SDL2.dll" "$run_root/$arch/SDL2.dll"
  install -m 0644 "$SDL/$sdl_arch/SDL3.dll" "$run_root/$arch/SDL3.dll"
}

build_fixture aarch64 aarch64-w64-mingw32-clang aarch64
build_fixture arm64ec arm64ec-w64-mingw32-clang arm64ec
build_fixture x86_64 x86_64-w64-mingw32-clang x86_64
build_fixture i386 i686-w64-mingw32-clang i386
"$TOOL/x86_64-w64-mingw32-clang" -O2 -msse2 \
  "$VKMT/test/x64emu/movnt_x64.c" -o "$run_root/x86_64/movnt_probe.exe"

check_machine "$run_root/aarch64/sdl2_probe.exe" IMAGE_FILE_MACHINE_ARM64
check_machine "$run_root/aarch64/sdl3_probe.exe" IMAGE_FILE_MACHINE_ARM64
check_machine "$run_root/arm64ec/sdl2_probe.exe" IMAGE_FILE_MACHINE_ARM64EC
check_machine "$run_root/arm64ec/sdl3_probe.exe" IMAGE_FILE_MACHINE_ARM64EC
check_machine "$run_root/x86_64/sdl2_probe.exe" IMAGE_FILE_MACHINE_AMD64
check_machine "$run_root/x86_64/sdl3_probe.exe" IMAGE_FILE_MACHINE_AMD64
check_machine "$run_root/x86_64/movnt_probe.exe" IMAGE_FILE_MACHINE_AMD64
check_machine "$run_root/i386/sdl2_probe.exe" IMAGE_FILE_MACHINE_I386
check_machine "$run_root/i386/sdl3_probe.exe" IMAGE_FILE_MACHINE_I386

system32="$prefix/drive_c/windows/system32"
syswow64="$prefix/drive_c/windows/syswow64"
mkdir -p "$system32" "$syswow64"
install -m 0644 "$XTAJIT64" "$system32/xtajit64.dll"
install -m 0644 "$XTAJIT" "$system32/xtajit.dll"
install -m 0644 "$WOW64" "$system32/wow64.dll"
install -m 0644 "$WOW64WIN" "$system32/wow64win.dll"
while IFS= read -r dll; do
  install -m 0644 "$dll" "$syswow64/$(basename "$dll")"
done < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print |
  LC_ALL=C sort)

run_wine "$run_root/wineboot.log" "$WINEBOOT" --init || {
  echo "SDL native ARM64 wineboot failed" >&2
  tail -n 160 "$run_root/wineboot.log" >&2
  exit 1
}

run_wine "$run_root/x86_64-movnt.log" "$run_root/x86_64/movnt_probe.exe" || {
  code=$?
  echo "SDL x64 non-temporal-store regression failed (status $code)" >&2
  tail -n 200 "$run_root/x86_64-movnt.log" >&2
  exit 1
}
grep -q 'VKMT_X64_MOVNT_OK' "$run_root/x86_64-movnt.log"
echo VKMT_SDL_X86_64_MOVNT_OK

PROBE_ARCHES="${VKMT_SDL_PROBE_ARCHES:-aarch64 arm64ec x86_64 i386}"
for arch in aarch64 arm64ec x86_64 i386; do
  case " $PROBE_ARCHES " in *" $arch "*) ;; *) continue ;; esac
  for family in sdl2 sdl3; do
    log="$run_root/$arch-$family.log"
    case "$family" in
      sdl2) family_marker=SDL2 ;;
      sdl3) family_marker=SDL3 ;;
    esac
    case "$arch" in
      aarch64) arch_marker=AARCH64 ;;
      arm64ec) arch_marker=ARM64EC ;;
      x86_64) arch_marker=X86_64 ;;
      i386) arch_marker=I386 ;;
    esac
    run_wine "$log" "$run_root/$arch/${family}_probe.exe" || {
      code=$?
      echo "SDL gate failed: $arch $family (status $code)" >&2
      grep -i "$family" "$log" | head -n 20 >&2 || true
      tail -n 200 "$log" >&2
      exit 1
    }
    grep -q "VKMT_${family_marker}_RUNTIME_OK" "$log" || {
      echo "SDL success marker missing: $arch $family" >&2
      tail -n 200 "$log" >&2
      exit 1
    }
    echo "VKMT_${family_marker}_${arch_marker}_OK"
  done
done

run_succeeded=1
echo VKMT_SDL2_SDL3_ALL_ARCHITECTURES_OK
