#!/bin/bash
# P8 provider baseline: prove ARM64, ARM64EC, x86_64, and i386 in one prefix.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
RUNS="$VKMT/build/probe-runs"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
XTAJIT64="${VKMT_XTAJIT64_SOURCE:-$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll}"
XTAJIT="${VKMT_XTAJIT_SOURCE:-$BUILD/dlls/xtajit/aarch64-windows/xtajit.dll}"
WOW64="$BUILD/dlls/wow64/aarch64-windows/wow64.dll"
WOW64WIN="$BUILD/dlls/wow64win/aarch64-windows/wow64win.dll"
prepared_prefix=
skip_i386=0
while test "$#" -gt 0; do
  case "$1" in
    --prefix) test "$#" -ge 2 || { echo "--prefix needs a path" >&2; exit 2; }; prepared_prefix=$2; shift 2 ;;
    --fresh) test -z "$prepared_prefix" || { echo "--fresh conflicts with --prefix" >&2; exit 2; }; shift ;;
    --skip-i386) skip_i386=1; shift ;;
    --evidence-dir) test "$#" -ge 2 || { echo "--evidence-dir needs a path" >&2; exit 2; }; VKMT_P8_EVIDENCE_DIR=$2; export VKMT_P8_EVIDENCE_DIR; shift 2 ;;
    *) echo "usage: $0 [--fresh | --prefix PATH] [--skip-i386] [--evidence-dir PATH]" >&2; exit 2 ;;
  esac
done

required_files=("$WINE" "$WINESERVER" "$WINEBOOT" "$XTAJIT64" "$XTAJIT" \
  "$WOW64" "$WOW64WIN" "$VKMT/test/aarch64_smoke.c" \
  "$VKMT/test/x64emu/hello_ec.c" "$VKMT/test/x64emu/entry_x64.c")
test "$skip_i386" = 1 || required_files+=("$VKMT/test/i386_smoke.c")
for required in "${required_files[@]}"; do
  test -e "$required" || { echo "Missing P8 provider input: $required" >&2; exit 1; }
done

for macho in "$WINE" "$WINESERVER" "$BUILD/dlls/ntdll/ntdll.so"; do
  test "$(/usr/bin/lipo -archs "$macho")" = arm64 || {
    echo "Non-ARM64 host artifact: $macho" >&2
    exit 1
  }
done
if translated="$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null)"; then
  test "$translated" = 0 || { echo "P8 provider runner is under Rosetta" >&2; exit 1; }
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
run_root="$(mktemp -d "$RUNS/p8-single-prefix.XXXXXX")"
prefix="${prepared_prefix:-$run_root/prefix}"
wine_pid=""
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=10s "${VKMT_P8_TIMEOUT:-120}s")
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=10s "${VKMT_P8_TIMEOUT:-120}s")
fi

cleanup()
{
  status=$?
  test -z "$wine_pid" || kill -TERM "$wine_pid" 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  if test -n "${VKMT_P8_EVIDENCE_DIR:-}"; then
    case "$VKMT_P8_EVIDENCE_DIR" in
      "$VKMT"/*)
        mkdir -p "$VKMT_P8_EVIDENCE_DIR"
        if test -f "$prefix/.vkmt/receipt.json"; then
          cp "$prefix/.vkmt/receipt.json" "$VKMT_P8_EVIDENCE_DIR/prefix-receipt.json"
        fi
        {
          printf 'command=%q ' "$0" "$@"
          printf '\nprepared_prefix=%s\n' "${prepared_prefix:-fresh}"
          printf 'host_arch=%s\n' "$(uname -m)"
          printf 'FEX_TSOENABLED=%s\n' "${FEX_TSOENABLED:-0}"
          printf 'FEX_VECTORTSOENABLED=%s\n' "${FEX_VECTORTSOENABLED:-0}"
          printf 'FEX_MEMCPYSETTSOENABLED=%s\n' "${FEX_MEMCPYSETTSOENABLED:-0}"
        } >"$VKMT_P8_EVIDENCE_DIR/environment.txt"
        find "$run_root" -maxdepth 1 -type f -name '*.log' \
          -exec cp {} "$VKMT_P8_EVIDENCE_DIR"/ \;
        find "$prefix" -type f -name 'fex-*.log' -exec sh -c '
          for log do cp "$log" "$1/fex-$(basename "$(dirname "$log")")-$(basename "$log")"; done
        ' sh "$VKMT_P8_EVIDENCE_DIR" {} +
        printf 'status=%s\n' "$status" >"$VKMT_P8_EVIDENCE_DIR/status.txt"
        ;;
      *) echo "Refusing non-VKMT evidence directory: $VKMT_P8_EVIDENCE_DIR" >&2 ;;
    esac
  fi
  case "$run_root" in
    "$RUNS"/*)
      if test "${VKMT_KEEP_P8_RUN:-0}" = 1; then
        echo "Retained disposable P8 provider run: $run_root" >&2
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
    WINEBOOTSTRAPMODE=1 WINE_NO_EXPLORER=1 WINEDEBUG="${VKMT_P8_WINEDEBUG:--all}" \
    FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
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
if test "$skip_i386" = 0; then
  "$TOOL/i686-w64-mingw32-clang" -O2 \
    -o "$run_root/i386.exe" "$VKMT/test/i386_smoke.c"
fi

specs=("arm64.exe:IMAGE_FILE_MACHINE_ARM64" \
  "arm64ec.exe:IMAGE_FILE_MACHINE_ARM64EC" \
  "x86_64.exe:IMAGE_FILE_MACHINE_AMD64")
test "$skip_i386" = 1 || specs+=("i386.exe:IMAGE_FILE_MACHINE_I386")
for spec in "${specs[@]}"; do
  file=${spec%%:*}
  expected=${spec#*:}
  machine="$("$TOOL/llvm-readobj" --file-headers "$run_root/$file" |
    awk '/Machine:/ {print $2; exit}')"
  test "$machine" = "$expected" || {
    echo "Wrong fixture architecture: $file ($machine, expected $expected)" >&2
    exit 1
  }
done

if test -n "$prepared_prefix"; then
  "$VKMT/scripts/vkmt-prefix" verify --prefix "$prefix"
else
  system32="$prefix/drive_c/windows/system32"
  syswow64="$prefix/drive_c/windows/syswow64"
  mkdir -p "$system32" "$syswow64"
  install -m 0644 "$XTAJIT64" "$system32/xtajit64.dll"
  install -m 0644 "$XTAJIT" "$system32/xtajit.dll"
  install -m 0644 "$WOW64" "$system32/wow64.dll"
  install -m 0644 "$WOW64WIN" "$system32/wow64win.dll"
  while IFS= read -r dll; do install -m 0644 "$dll" "$syswow64/$(basename "$dll")"; done < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)
  "$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
  run_wine "$run_root/wineboot.log" "$WINEBOOT" --init || { echo "P8 provider wineboot failed" >&2; tail -n 120 "$run_root/wineboot.log" >&2; exit 1; }
  "$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
  "$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"
fi

run_wine "$run_root/arm64.log" "$run_root/arm64.exe" || {
  echo "P8 provider ARM64 baseline failed" >&2
  tail -n 120 "$run_root/arm64.log" >&2
  exit 1
}
grep -q 'VKMT native AArch64 smoke passed' "$run_root/arm64.log"
echo P8_SINGLE_PREFIX_ARM64_OK

run_wine "$run_root/arm64ec.log" "$run_root/arm64ec.exe" || {
  arm64ec_code=$?
  echo "P8 provider ARM64EC rc=0 baseline failed with status $arm64ec_code" >&2
  tail -n 120 "$run_root/arm64ec.log" >&2
  exit 1
}
grep -q 'hello from arm64ec' "$run_root/arm64ec.log"
echo P8_SINGLE_PREFIX_ARM64EC_OK

run_wine "$run_root/x86_64.log" "$run_root/x86_64.exe" || {
  x64_code=$?
  echo "P8 provider x86_64 rc=0 baseline failed with status $x64_code" >&2
  tail -n 120 "$run_root/x86_64.log" >&2
  exit 1
}
grep -q 'VKMT entry_x64: hello from x86-64 guest' "$run_root/x86_64.log"
echo P8_SINGLE_PREFIX_X86_64_OK

if test "$skip_i386" = 0; then
  run_wine "$run_root/i386.log" "$run_root/i386.exe" "Z:$run_root/i386.marker" || {
    echo "P8 provider i386 baseline failed" >&2
    tail -n 120 "$run_root/i386.log" >&2
    exit 1
  }
  for _ in $(seq 1 "${VKMT_P8_MARKER_WAIT:-60}"); do
    test -f "$run_root/i386.marker" && break
    sleep 1
  done
  grep -q 'VKMT i386 WoW64 execution contract passed' "$run_root/i386.marker"
  echo P8_SINGLE_PREFIX_I386_OK
else
  echo P8_SINGLE_PREFIX_I386_SKIPPED
fi

if test "$skip_i386" = 0; then
  echo P8_SINGLE_PREFIX_ALL_ARCHITECTURES_OK
else
  echo P8_SINGLE_PREFIX_NONWOW64_ARCHITECTURES_OK
fi
