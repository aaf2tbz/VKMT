#!/bin/bash
# Phase 5: i386 DXVK/vkd3d-proton -> ARM64 Wine Vulkan -> MoltenVK -> Metal.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
DXVK="$VKMT/third_party/dxvk/runtime/dxvk-vkmt-1a5919b/x32"
VKD3D="$VKMT/third_party/vkd3d-proton/install-win32/bin"
MOLTENVK="$VKMT/third_party/MoltenVK/Package/Release/MoltenVK/dynamic/dylib/macOS/libMoltenVK.dylib"
RUNS="$VKMT/build/probe-runs"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
XTAJIT="$BUILD/dlls/xtajit/aarch64-windows/xtajit.dll"
WOW64="$BUILD/dlls/wow64/aarch64-windows/wow64.dll"
WOW64WIN="$BUILD/dlls/wow64win/aarch64-windows/wow64win.dll"
FREETYPE="$BUILD/dlls/win32u/libfreetype.6.dylib"
LIBPNG="$BUILD/dlls/win32u/libpng16.16.dylib"

for file in "$WINE" "$WINESERVER" "$WINEBOOT" "$XTAJIT" "$WOW64" "$WOW64WIN" \
    "$DXVK/dxgi.dll" "$DXVK/d3d11.dll" "$VKD3D/d3d12.dll" \
    "$VKD3D/d3d12core.dll" "$MOLTENVK" "$FREETYPE" "$LIBPNG"; do
  test -e "$file" || { echo "Missing Phase 5 input: $file" >&2; exit 1; }
done

for macho in "$WINE" "$WINESERVER" "$BUILD/dlls/ntdll/ntdll.so" \
    "$BUILD/dlls/win32u/win32u.so" "$BUILD/dlls/winevulkan/winevulkan.so" \
    "$FREETYPE" "$LIBPNG"; do
  test "$(/usr/bin/lipo -archs "$macho")" = arm64 || {
    echo "Non-ARM64 host artifact: $macho" >&2; exit 1;
  }
done
if translated="$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null)"; then
  test "$translated" = 0 || {
    echo "Phase 5 runner is executing through Rosetta" >&2
    exit 1
  }
fi
/usr/bin/otool -L "$FREETYPE" | grep -Fq '@loader_path/libpng16.16.dylib' || {
  echo "FreeType does not resolve staged libpng relatively" >&2; exit 1;
}
if /usr/bin/otool -L "$FREETYPE" "$LIBPNG" | grep -Fq /opt/homebrew/; then
  echo "Phase 5 host dependency closure contains a Homebrew runtime path" >&2
  exit 1
fi
for pe in "$XTAJIT" "$WOW64" "$WOW64WIN"; do
  machine="$($TOOL/llvm-readobj --file-headers "$pe" | awk '/Machine:/ {print $2; exit}')"
  test "$machine" = IMAGE_FILE_MACHINE_ARM64 || {
    echo "Not native ARM64 PE: $pe ($machine)" >&2; exit 1;
  }
done
for pe in "$DXVK/dxgi.dll" "$DXVK/d3d11.dll" "$VKD3D/d3d12.dll" "$VKD3D/d3d12core.dll"; do
  machine="$($TOOL/llvm-readobj --file-headers "$pe" | awk '/Machine:/ {print $2; exit}')"
  test "$machine" = IMAGE_FILE_MACHINE_I386 || { echo "Not i386 PE: $pe ($machine)" >&2; exit 1; }
done

mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/p5-i386-vkmt.XXXXXX")"
prefix="$run_root/prefix"
wine_pid=""
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=10s "${VKMT_P5_TIMEOUT:-180}s")
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=10s "${VKMT_P5_TIMEOUT:-180}s")
fi

cleanup()
{
  status=$?
  test -z "$wine_pid" || kill -TERM "$wine_pid" 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  case "$run_root" in
    "$RUNS"/*)
      if test "${VKMT_KEEP_P5_RUN:-0}" = 1; then
        echo "Retained disposable Phase 5 run: $run_root" >&2
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
  debug=$2
  shift 2
  "${timeout_cmd[@]}" env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
    WINE_NO_EXPLORER=1 WINEDEBUG="$debug" VK_ICD_FILENAMES="$run_root/vkmt_icd.json" \
    WINEDLLOVERRIDES='dxgi,d3d11,d3d12,d3d12core=n' \
    DXVK_LOG_LEVEL=info DXVK_LOG_PATH="$run_root" VKD3D_DEBUG=info \
    VKMT_ALLOW_NON_SINGLE_TEXEL_ALIGNMENT=1 \
    "$WINE" "$@" >"$output" 2>&1 &
  wine_pid=$!
  if wait "$wine_pid"; then code=0; else code=$?; fi
  wine_pid=""
  return "$code"
}

mkdir -p "$prefix/drive_c/windows/system32" "$prefix/drive_c/windows/syswow64"
install -m 0644 "$XTAJIT" "$prefix/drive_c/windows/system32/xtajit.dll"
install -m 0644 "$WOW64" "$prefix/drive_c/windows/system32/wow64.dll"
install -m 0644 "$WOW64WIN" "$prefix/drive_c/windows/system32/wow64win.dll"
while IFS= read -r dll; do
  install -m 0644 "$dll" "$prefix/drive_c/windows/syswow64/$(basename "$dll")"
done < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)

/usr/bin/lipo "$MOLTENVK" -thin arm64 -output "$run_root/libMoltenVK-arm64.dylib"
test "$(/usr/bin/lipo -archs "$run_root/libMoltenVK-arm64.dylib")" = arm64
cat >"$run_root/vkmt_icd.json" <<EOF
{"ICD":{"api_version":"1.4.0","is_portability_driver":true,"library_path":"$run_root/libMoltenVK-arm64.dylib"},"file_format_version":"1.0.0"}
EOF

"$TOOL/i686-w64-mingw32-clang" -O2 -g -o "$run_root/load.exe" "$VKMT/test/i386_vkmt_load_probe.c"
"$TOOL/i686-w64-mingw32-clang" -O2 -g -o "$run_root/substrate.exe" "$VKMT/test/i386_smoke.c"
"$TOOL/i686-w64-mingw32-clang" -O2 -g -o "$run_root/dxgi.exe" "$VKMT/test/i386_vkmt_dxgi_probe.c"
"$TOOL/i686-w64-mingw32-clang" -O2 -g -o "$run_root/d3d12.exe" "$VKMT/test/d3d12_probe_nodxgi.c" -ld3d12 -ldxguid
"$TOOL/i686-w64-mingw32-clang" -O2 -g -o "$run_root/d3d11.exe" "$VKMT/test/d3d11_probe.c" -ld3d11 -ldxgi
for pe in "$run_root"/*.exe; do
  "$TOOL/llvm-readobj" --file-headers "$pe" | grep -q 'IMAGE_FILE_MACHINE_I386'
done

run_wine "$run_root/wineboot.log" -all "$WINEBOOT" --init || {
  echo "P5 native ARM64 wineboot failed" >&2; tail -n 100 "$run_root/wineboot.log" >&2; exit 1;
}
run_wine "$run_root/substrate.log" -all "$run_root/substrate.exe" "Z:$run_root/substrate.marker" || {
  echo "P5 i386 substrate regression failed" >&2; tail -n 120 "$run_root/substrate.log" >&2; exit 1;
}
for _ in $(seq 1 "${VKMT_P5_MARKER_WAIT:-60}"); do
  test -f "$run_root/substrate.marker" && break
  sleep 1
done
grep -q 'VKMT i386 WoW64 execution contract passed' "$run_root/substrate.marker"
install -m 0644 "$DXVK/dxgi.dll" "$DXVK/d3d11.dll" "$VKD3D/d3d12.dll" \
  "$VKD3D/d3d12core.dll" "$prefix/drive_c/windows/syswow64/"

load_marker="$run_root/load.marker"
run_wine "$run_root/load.log" "${VKMT_P5_LOAD_WINEDEBUG:--all}" "$run_root/load.exe" "Z:$load_marker" || {
  echo "P5 DLL/export load gate failed" >&2; tail -n 120 "$run_root/load.log" >&2; exit 1;
}
for _ in $(seq 1 "${VKMT_P5_MARKER_WAIT:-60}"); do
  if test -f "$load_marker" && grep -Eq 'P5_I386_DLL_LOAD_(DONE|FAILED)' "$load_marker"; then break; fi
  sleep 1
done
if test ! -f "$load_marker" || ! grep -q P5_I386_DLL_LOAD_DONE "$load_marker"; then
  echo "P5 DLL/export load process did not complete" >&2
  test ! -f "$load_marker" || sed -n '1,80p' "$load_marker" >&2
  tail -n 120 "$run_root/load.log" >&2
  exit 1
fi
for marker in P5_I386_DXGI_DLL_LOAD_OK P5_I386_D3D11_DLL_LOAD_OK \
    P5_I386_D3D12_DLL_LOAD_OK P5_I386_D3D12CORE_DLL_LOAD_OK; do
  grep -q "$marker" "$load_marker" || { echo "Missing $marker" >&2; exit 1; }
done

run_wine "$run_root/dxgi.log" -all "$run_root/dxgi.exe" || {
  echo "P5 DXGI gate failed" >&2; tail -n 160 "$run_root/dxgi.log" >&2; exit 1;
}
grep -q P5_I386_DXGI_FACTORY_OK "$run_root/dxgi.log"
grep -q P5_I386_DXGI_ADAPTER_OK "$run_root/dxgi.log"

run_wine "$run_root/d3d12.log" -all "$run_root/d3d12.exe" || {
  echo "P5 D3D12 gate failed" >&2; tail -n 200 "$run_root/d3d12.log" >&2; exit 1;
}
grep -q 'PROBE OK' "$run_root/d3d12.log"
grep -q '\[mvk-info\]' "$run_root/d3d12.log"
run_wine "$run_root/d3d12-repeat.log" -all "$run_root/d3d12.exe" || {
  echo "P5 repeated D3D12 gate failed" >&2
  tail -n 200 "$run_root/d3d12-repeat.log" >&2
  exit 1
}
grep -q 'PROBE OK' "$run_root/d3d12-repeat.log"
grep -q 'Readback expected=0x4b4d5456 actual=0x4b4d5456' "$run_root/d3d12-repeat.log"
grep -q '\[mvk-info\]' "$run_root/d3d12-repeat.log"

run_wine "$run_root/d3d11.log" -all "$run_root/d3d11.exe" || {
  echo "P5 D3D11 gate failed" >&2; tail -n 200 "$run_root/d3d11.log" >&2; exit 1;
}
grep -q VKMT_D3D11_PROBE_OK "$run_root/d3d11.log"
grep -q '\[mvk-info\]' "$run_root/d3d11.log"

echo P5_I386_DLL_LOAD_OK
echo P5_I386_DXGI_FACTORY_ADAPTER_OK
echo P5_I386_D3D12_DEVICE_QUEUE_FENCE_COPY_READBACK_OK
echo P5_I386_D3D11_DEVICE_CLEAR_COPY_READBACK_OK
echo P5_I386_VKMT_OK
