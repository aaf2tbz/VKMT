#!/bin/bash
# Phase 6 baseline: prove ARM64, ARM64EC, x86_64, and i386 in one prefix.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
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
    "$WOW64" "$WOW64WIN" "$VKMT/test/aarch64_smoke.c" \
    "$VKMT/test/x64emu/hello_ec.c" "$VKMT/test/x64emu/entry_x64.c" \
    "$VKMT/test/i386_smoke.c"; do
  test -e "$required" || { echo "Missing Phase 6 input: $required" >&2; exit 1; }
done

for macho in "$WINE" "$WINESERVER" "$BUILD/dlls/ntdll/ntdll.so"; do
  test "$(/usr/bin/lipo -archs "$macho")" = arm64 || {
    echo "Non-ARM64 host artifact: $macho" >&2
    exit 1
  }
done
if translated="$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null)"; then
  test "$translated" = 0 || { echo "Phase 6 runner is under Rosetta" >&2; exit 1; }
fi
for pe in "$XTAJIT64" "$XTAJIT" "$WOW64" "$WOW64WIN"; do
  machine="$("$TOOL/llvm-readobj" --file-headers "$pe" | awk '/Machine:/ {print $2; exit}')"
  case "$pe" in
    "$XTAJIT64") expected=IMAGE_FILE_MACHINE_ARM64EC ;;
    *) expected=IMAGE_FILE_MACHINE_ARM64 ;;
  esac
  test "$machine" = "$expected" || {
    echo "Wrong provider architecture: $pe ($machine, expected $expected)" >&2
    exit 1
  }
done

mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/p6-single-prefix.XXXXXX")"
prefix="$run_root/prefix"
wine_pid=""
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=10s "${VKMT_P6_TIMEOUT:-120}s")
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=10s "${VKMT_P6_TIMEOUT:-120}s")
fi

cleanup()
{
  status=$?
  test -z "$wine_pid" || kill -TERM "$wine_pid" 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  if test -n "${VKMT_P6_EVIDENCE_DIR:-}"; then
    case "$VKMT_P6_EVIDENCE_DIR" in
      "$VKMT"/*)
        mkdir -p "$VKMT_P6_EVIDENCE_DIR"
        find "$run_root" -maxdepth 1 -type f -name '*.log' \
          -exec cp {} "$VKMT_P6_EVIDENCE_DIR"/ \;
        find "$prefix" -type f -name 'fex-*.log' -exec sh -c '
          for log do cp "$log" "$1/fex-$(basename "$(dirname "$log")")-$(basename "$log")"; done
        ' sh "$VKMT_P6_EVIDENCE_DIR" {} +
        printf 'status=%s\n' "$status" >"$VKMT_P6_EVIDENCE_DIR/status.txt"
        ;;
      *) echo "Refusing non-VKMT evidence directory: $VKMT_P6_EVIDENCE_DIR" >&2 ;;
    esac
  fi
  case "$run_root" in
    "$RUNS"/*)
      if test "${VKMT_KEEP_P6_RUN:-0}" = 1; then
        echo "Retained disposable Phase 6 run: $run_root" >&2
      else
        find "$run_root" -depth -delete 2>/dev/null || true
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
    WINEBOOTSTRAPMODE=1 WINE_NO_EXPLORER=1 WINEDEBUG="${VKMT_P6_WINEDEBUG:--all}" \
    "$WINE" "$@" >"$output" 2>&1 &
  wine_pid=$!
  if wait "$wine_pid"; then code=0; else code=$?; fi
  wine_pid=""
  return "$code"
}

"$TOOL/aarch64-w64-mingw32-clang" -O2 -ffixed-x18 -ffixed-x28 \
  -o "$run_root/arm64.exe" "$VKMT/test/aarch64_smoke.c"
"$TOOL/arm64ec-w64-mingw32-clang" -O2 -ffixed-x18 -ffixed-x28 \
  -o "$run_root/arm64ec.exe" "$VKMT/test/x64emu/hello_ec.c"
"$TOOL/x86_64-w64-mingw32-clang" -O2 \
  -o "$run_root/x86_64.exe" "$VKMT/test/x64emu/entry_x64.c"
"$TOOL/i686-w64-mingw32-clang" -O2 \
  -o "$run_root/i386.exe" "$VKMT/test/i386_smoke.c"

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
    echo "Wrong fixture architecture: $file ($machine, expected $expected)" >&2
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

"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
run_wine "$run_root/wineboot.log" "$WINEBOOT" --init || {
  echo "Phase 6 wineboot failed" >&2
  tail -n 120 "$run_root/wineboot.log" >&2
  exit 1
}
"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"

run_wine "$run_root/arm64.log" "$run_root/arm64.exe" || {
  echo "Phase 6 ARM64 baseline failed" >&2
  tail -n 120 "$run_root/arm64.log" >&2
  exit 1
}
grep -q 'VKMT native AArch64 smoke passed' "$run_root/arm64.log"
echo P6_SINGLE_PREFIX_ARM64_OK

if run_wine "$run_root/arm64ec.log" "$run_root/arm64ec.exe"; then
  arm64ec_code=0
else
  arm64ec_code=$?
fi
test "$arm64ec_code" = 42 || {
  echo "Phase 6 ARM64EC baseline failed with status $arm64ec_code" >&2
  tail -n 120 "$run_root/arm64ec.log" >&2
  exit 1
}
grep -q 'hello from arm64ec' "$run_root/arm64ec.log"
echo P6_SINGLE_PREFIX_ARM64EC_OK

if run_wine "$run_root/x86_64.log" "$run_root/x86_64.exe"; then
  x64_code=0
else
  x64_code=$?
fi
test "$x64_code" = 7 || {
  echo "Phase 6 x86_64 baseline failed with status $x64_code" >&2
  tail -n 120 "$run_root/x86_64.log" >&2
  exit 1
}
grep -q 'VKMT entry_x64: hello from x86-64 guest' "$run_root/x86_64.log"
echo P6_SINGLE_PREFIX_X86_64_OK

run_wine "$run_root/i386.log" "$run_root/i386.exe" "Z:$run_root/i386.marker" || {
  echo "Phase 6 i386 baseline failed" >&2
  tail -n 120 "$run_root/i386.log" >&2
  exit 1
}
for _ in $(seq 1 "${VKMT_P6_MARKER_WAIT:-60}"); do
  test -f "$run_root/i386.marker" && break
  sleep 1
done
grep -q 'VKMT i386 WoW64 execution contract passed' "$run_root/i386.marker"
echo P6_SINGLE_PREFIX_I386_OK

echo P6_SINGLE_PREFIX_ALL_ARCHITECTURES_OK
