#!/bin/bash
# Prove pinned CEF 109, the MetalSharp launcher wrapper, and child hook for
# x86_64 and i386/WoW64 in one disposable native-ARM64 Wine prefix.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
RUNS="$VKMT/build/probe-runs"
TOOLCHAIN="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
VERSION='109.1.18+gf1c41e4+chromium-109.0.5414.120'
CEF="$VKMT/third_party/cef-$VERSION"
COMPAT="$VKMT/build/cef-compat"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"

"$VKMT/scripts/fetch-cef-runtime.sh"
"$VKMT/scripts/build-metalsharp-cef-compat.sh"
mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/cef-runtime.XXXXXX")"
prefix="$run_root/prefix"

cleanup()
{
  status=$?
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  case "$run_root" in "$RUNS"/*)
    test "${VKMT_KEEP_PROBE_RUN:-0}" = 1 ||
      /usr/bin/trash "$run_root" 2>/dev/null || true
  esac
  exit "$status"
}
trap cleanup EXIT

run_wine()
{
  output=$1
  timeout=$2
  shift 2
  gtimeout --signal=TERM --kill-after=10s "$timeout" \
    env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
      DYLD_LIBRARY_PATH="$BUILD/dlls/winecoreaudio.drv:$BUILD/dlls/secur32:$BUILD/dlls/ntdll:$BUILD/dlls/win32u${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}" \
      WINEDEBUG="${VKMT_CEF_WINEDEBUG:--all}" "$WINE" "$@" >"$output" 2>&1
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

mkdir -p "$prefix/drive_c/windows/system32" "$prefix/drive_c/windows/syswow64"
for dll in xtajit64 xtajit wow64 wow64win; do
  install -m 0644 "$BUILD/dlls/$dll/aarch64-windows/$dll.dll" \
    "$prefix/drive_c/windows/system32/$dll.dll"
done
while IFS= read -r dll; do
  install -m 0644 "$dll" "$prefix/drive_c/windows/syswow64/$(basename "$dll")"
done < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)

"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
run_wine "$run_root/wineboot.log" "${VKMT_CEF_BOOT_TIMEOUT:-120}s" "$WINEBOOT" --init
stop_server
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"

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
    case "$name" in cefclient.exe|chrome_elf.dll) continue ;; esac
    ln -s "$item" "$client/$name"
  done
  if test -d "$CEF/windows$bits/Resources"; then
    for item in "$CEF/windows$bits/Resources"/*; do
      name="$(basename "$item")"
      test -e "$client/$name" || ln -s "$item" "$client/$name"
    done
  fi
  ln -s "$release/cefclient.exe" "$client/cefclient.exe"
  install -m 0644 "$COMPAT/$arch/chrome_elf.dll" "$client/chrome_elf.dll"

  find "$prefix/drive_c/users" -type f \
    \( -name metalsharp-cefchildhook.log -o -name metalsharp-chrome-elf-compat.log \) \
    -exec unlink {} \;
  set +e
  run_wine "$run_root/$arch-client.log" "${VKMT_CEF_CLIENT_WINDOW:-90}s" \
    "$client/cefclient.exe" --no-sandbox --disable-gpu \
    --disable-gpu-compositing --url=data:text/html,VKMT_CEF_RUNTIME_OK \
    "--log-file=$(winpath "$run_root/$arch-cef.log")"
  client_status=$?
  set -e
  stop_server

  elf_log="$(find "$prefix/drive_c/users" -type f -name metalsharp-chrome-elf-compat.log -print -quit)"
  test -f "$elf_log"
  grep -q 'chrome_elf compatibility DLL loaded' "$elf_log"
  grep -Eq 'command: .*--type=(renderer|utility|gpu-process)' "$elf_log"
  test -f "$run_root/$arch-cef.log"
  test -s "$run_root/$arch-cef.log"
  case "$client_status" in
    0|124|143) ;;
    *)
      # Wine may deliver the observation-window TERM to the PE child and
      # return that child's code. Runtime evidence above is authoritative.
      echo "CEF_${arch_marker}_OBSERVATION_EXIT_$client_status"
      ;;
  esac
  echo "CEF_${arch_marker}_SUBPROCESS_RUNTIME_OK"
done

echo CEF_X64_I386_ALL_OK
