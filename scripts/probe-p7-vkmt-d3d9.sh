#!/bin/bash
# Phase 7: prove DXVK D3D9 loading and adapter enumeration in one prefix.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
DXVK_ROOT="$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b"
DXVK_ARM64="$DXVK_ROOT/aarch64/d3d9.dll"
DXVK_ARM64EC="$DXVK_ROOT/arm64ec/d3d9.dll"
DXVK_I386="$DXVK_ROOT/x32/d3d9.dll"
MOLTENVK="$VKMT/third_party/MoltenVK/Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib"
RUNS="$VKMT/build/probe-runs"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
XTAJIT64="$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll"
XTAJIT="$BUILD/dlls/xtajit/aarch64-windows/xtajit.dll"
WOW64="$BUILD/dlls/wow64/aarch64-windows/wow64.dll"
WOW64WIN="$BUILD/dlls/wow64win/aarch64-windows/wow64win.dll"

for required in "$WINE" "$WINESERVER" "$WINEBOOT" "$XTAJIT64" "$XTAJIT" \
    "$WOW64" "$WOW64WIN" "$DXVK_ARM64" "$DXVK_ARM64EC" "$DXVK_I386" \
    "$MOLTENVK" "$VKMT/test/d3d9_probe.c"; do
  test -e "$required" || {
    echo "Missing Phase 7 input: $required" >&2
    exit 1
  }
done

for macho in "$WINE" "$WINESERVER" "$BUILD/dlls/ntdll/ntdll.so" \
    "$BUILD/dlls/winevulkan/winevulkan.so"; do
  test "$(/usr/bin/lipo -archs "$macho")" = arm64 || {
    echo "Non-ARM64 host artifact: $macho" >&2
    exit 1
  }
done
if translated="$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null)"; then
  test "$translated" = 0 || {
    echo "Phase 7 runner is under Rosetta" >&2
    exit 1
  }
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
check_machine "$DXVK_ARM64" IMAGE_FILE_MACHINE_ARM64
check_machine "$DXVK_ARM64EC" IMAGE_FILE_MACHINE_ARM64EC
check_machine "$DXVK_I386" IMAGE_FILE_MACHINE_I386

mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/p7-vkmt-d3d9.XXXXXX")"
prefix="$run_root/prefix"
wine_pid=""
run_succeeded=0
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=10s "${VKMT_P7_TIMEOUT:-180}s")
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=10s "${VKMT_P7_TIMEOUT:-180}s")
fi

cleanup()
{
  status=$?
  test -z "$wine_pid" || kill -TERM "$wine_pid" 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  case "$run_root" in
    "$RUNS"/*)
      if test "$run_succeeded" = 1 && test "${VKMT_KEEP_P7_RUN:-0}" = 1; then
        echo "Retained successful disposable Phase 7 run: $run_root" >&2
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
  arch=$1
  output=$2
  shift 2
  mkdir -p "$run_root/dxvk-logs/$arch"
  "${timeout_cmd[@]}" env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" \
    WINEBOOTSTRAPMODE=1 WINE_NO_EXPLORER=1 WINEDEBUG=-all \
    VK_ICD_FILENAMES="$run_root/vkmt_icd.json" WINEDLLOVERRIDES='d3d9=n' \
    DXVK_LOG_LEVEL=info DXVK_LOG_PATH="$run_root/dxvk-logs/$arch" \
    "$WINE" "$@" >"$output" 2>&1 &
  wine_pid=$!
  if wait "$wine_pid"; then code=0; else code=$?; fi
  wine_pid=""
  return "$code"
}

require_log()
{
  pattern=$1
  log=$2
  label=$3
  grep -q "$pattern" "$log" || {
    echo "Phase 7 missing $label in $log" >&2
    tail -n 200 "$log" >&2
    exit 1
  }
}

require_dxvk_log()
{
  pattern=$1
  arch=$2
  label=$3
  if grep -q "$pattern" "$run_root/$arch.log" ||
      grep -Rqs "$pattern" "$run_root/dxvk-logs/$arch"; then
    return
  fi
  echo "Phase 7 missing $label for $arch" >&2
  tail -n 200 "$run_root/$arch.log" >&2
  find "$run_root/dxvk-logs/$arch" -type f -maxdepth 1 -print -exec tail -n 80 {} \; >&2
  exit 1
}

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

/usr/bin/lipo "$MOLTENVK" -thin arm64 -output "$run_root/libMoltenVK-arm64.dylib"
test "$(/usr/bin/lipo -archs "$run_root/libMoltenVK-arm64.dylib")" = arm64
cat >"$run_root/vkmt_icd.json" <<EOF
{"ICD":{"api_version":"1.4.0","is_portability_driver":true,"library_path":"$run_root/libMoltenVK-arm64.dylib"},"file_format_version":"1.0.0"}
EOF

build_fixture()
{
  arch=$1
  compiler=$2
  d3d9=$3
  mkdir -p "$run_root/$arch"
  case "$arch" in
    arm64|arm64ec)
      "$TOOL/$compiler" -O2 -g -ffixed-x18 -ffixed-x28 \
        -o "$run_root/$arch/d3d9_probe.exe" "$VKMT/test/d3d9_probe.c"
      ;;
    *)
      "$TOOL/$compiler" -O2 -g \
        -o "$run_root/$arch/d3d9_probe.exe" "$VKMT/test/d3d9_probe.c"
      ;;
  esac
  install -m 0644 "$d3d9" "$run_root/$arch/d3d9.dll"
}
build_fixture arm64 aarch64-w64-mingw32-clang "$DXVK_ARM64"
build_fixture arm64ec arm64ec-w64-mingw32-clang "$DXVK_ARM64EC"
build_fixture x86_64 x86_64-w64-mingw32-clang "$DXVK_ARM64EC"
build_fixture i386 i686-w64-mingw32-clang "$DXVK_I386"

check_machine "$run_root/arm64/d3d9_probe.exe" IMAGE_FILE_MACHINE_ARM64
check_machine "$run_root/arm64ec/d3d9_probe.exe" IMAGE_FILE_MACHINE_ARM64EC
check_machine "$run_root/x86_64/d3d9_probe.exe" IMAGE_FILE_MACHINE_AMD64
check_machine "$run_root/i386/d3d9_probe.exe" IMAGE_FILE_MACHINE_I386

"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
run_wine bootstrap "$run_root/wineboot.log" "$WINEBOOT" --init || {
  echo "Phase 7 native ARM64 wineboot failed" >&2
  tail -n 120 "$run_root/wineboot.log" >&2
  exit 1
}
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"

for arch in arm64 arm64ec x86_64 i386; do
  run_wine "$arch" "$run_root/$arch.log" "$run_root/$arch/d3d9_probe.exe" || {
    echo "Phase 7 $arch D3D9 gate failed" >&2
    tail -n 200 "$run_root/$arch.log" >&2
    exit 1
  }
  require_log 'VKMT_D3D9_LOAD_ADAPTER_OK' "$run_root/$arch.log" \
    'D3D9 interface/adapter/caps marker'
  require_dxvk_log 'DXVK: 3.0.2' "$arch" 'DXVK revision'
  require_dxvk_log 'Found device: Apple M4' "$arch" 'Apple M4 adapter'
  require_log '\[mvk-info\]' "$run_root/$arch.log" 'MoltenVK backend evidence'
  case "$arch" in
    arm64) marker=P7_VKMT_D3D9_ARM64_OK ;;
    arm64ec) marker=P7_VKMT_D3D9_ARM64EC_OK ;;
    x86_64) marker=P7_VKMT_D3D9_X86_64_OK ;;
    i386) marker=P7_VKMT_D3D9_I386_OK ;;
  esac
  echo "$marker"
done

run_succeeded=1
echo P7_VKMT_D3D9_ALL_ARCHITECTURES_OK
