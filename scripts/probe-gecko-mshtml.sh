#!/bin/bash
# Prove Gecko-backed MSHTML for x86_64 and i386/WoW64 in one prefix.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$VKMT/wine/build-ec"
RUNS="$VKMT/build/probe-runs"
TOOLCHAIN="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
PROVIDERS="$VKMT/scripts/stage-runtime-providers.sh"

"$VKMT/scripts/stage-gecko-runtime.sh"
mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/gecko-mshtml.XXXXXX")"
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
  shift
  wine_env=(
    WINEPREFIX="$prefix"
    WINEBUILDDIR="$BUILD"
    WINEBOOTSTRAPMODE=1
    FEX_ENABLECODECACHINGWIP=0
    FEX_SILENTLOG=1
    DYLD_LIBRARY_PATH="$BUILD/dlls/secur32:$BUILD/dlls/ntdll:$BUILD/dlls/win32u${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
    WINEDEBUG="${VKMT_RUN_WINEDEBUG:-${VKMT_GECKO_WINEDEBUG:--all}}"
  )
  if test "${VKMT_RUN_NO_EXPLORER:-0}" = 1; then
    wine_env+=(WINE_NO_EXPLORER=1)
  fi
  if gtimeout --signal=TERM --kill-after=10s \
      "${VKMT_RUN_TIMEOUT:-${VKMT_GECKO_TIMEOUT:-90}}s" \
      env "${wine_env[@]}" "$WINE" "$@" >"$output" 2>&1
  then
    return 0
  else
    status=$?
  fi
  install -m 0644 "$output" "$VKMT/build/gecko-mshtml.latest.log"
  echo "Wine stage failed: $output (status $status)" >&2
  return "$status"
}
stop_server()
{
  WINEPREFIX="$prefix" "$WINESERVER" -k
  WINEPREFIX="$prefix" "$WINESERVER" -w
}

mkdir -p "$prefix/drive_c/windows/system32" "$prefix/drive_c/windows/syswow64"
"$PROVIDERS" --prefix "$prefix"
for dll in wow64 wow64win; do
  install -m 0644 "$BUILD/dlls/$dll/aarch64-windows/$dll.dll" \
    "$prefix/drive_c/windows/system32/$dll.dll"
done
while IFS= read -r dll; do
  install -m 0644 "$dll" "$prefix/drive_c/windows/syswow64/$(basename "$dll")"
done < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)

VKMT_RUN_NO_EXPLORER=1
VKMT_RUN_TIMEOUT="${VKMT_GECKO_BOOT_TIMEOUT:-180}"
run_wine "$run_root/wineboot.log" "$WINEBOOT" --init
unset VKMT_RUN_NO_EXPLORER VKMT_RUN_TIMEOUT
stop_server
"$PROVIDERS" --verify-prefix "$prefix"

gecko_x86="$(printf 'Z:%s' "$VKMT/wine/gecko/wine-gecko-2.47.4-x86" | tr '/' '\\')"
gecko_x86_64="$(printf 'Z:%s' "$VKMT/wine/gecko/wine-gecko-2.47.4-x86_64" | tr '/' '\\')"
gecko_key='HKLM\Software\Wine\MSHTML\2.47.4'
run_wine "$run_root/gecko-registry-x86_64.log" reg.exe add "$gecko_key" \
  /v GeckoPath /t REG_SZ /d "$gecko_x86_64" /f /reg:64
stop_server
run_wine "$run_root/gecko-registry-x86.log" \
  "$BUILD/programs/reg/i386-windows/reg.exe" add "$gecko_key" \
  /v GeckoPath /t REG_SZ /d "$gecko_x86" /f /reg:32
stop_server
echo GECKO_REGISTRY_X64_I386_OK

# Gecko and CEF both depend on x64 SEH during worker startup.  Keep this
# focused contract ahead of the expensive browser initialization so a JIT or
# exception-frame regression fails quickly and unambiguously.
seh_probe="$run_root/seh-x86_64.exe"
"$TOOLCHAIN/x86_64-w64-mingw32-gcc" -O2 -Wall -Wextra -fms-extensions \
  "$VKMT/test/x64emu/seh_x64.c" -o "$seh_probe"
run_wine "$run_root/seh-x86_64.log" "$seh_probe"
grep -q 'seh_x64: OK (0 failures)' "$run_root/seh-x86_64.log"
stop_server
echo GECKO_PREREQ_X86_64_SEH_OK

i386_cc="$TOOLCHAIN/i686-w64-mingw32-gcc"
i386_time="$run_root/time-i386.exe"
i386_socket="$run_root/socket-poll-i386.exe"
i386_dns="$run_root/dns-i386.exe"
i386_https="$run_root/https-i386.exe"
"$i386_cc" -O2 -Wall -Wextra "$VKMT/test/i386/time_progress.c" -o "$i386_time"
"$i386_cc" -O2 -Wall -Wextra "$VKMT/test/i386/socket_poll_wakeup.c" \
  -o "$i386_socket" -lws2_32
"$i386_cc" -O2 -Wall -Wextra -municode "$VKMT/test/i386/dns_resolution.c" \
  -o "$i386_dns" -lws2_32
"$i386_cc" -O2 -Wall -Wextra "$VKMT/test/gnutls_https_probe.c" \
  -o "$i386_https" -lsecur32 -lwinhttp
for prerequisite in \
  "time:$i386_time:I386_TIME_PROGRESS_OK" \
  "socket:$i386_socket:I386_SOCKET_POLL_OK" \
  "dns:$i386_dns:I386_DNS_OK" \
  "https:$i386_https:GNUTLS_HTTPS_ALL_OK"; do
  IFS=: read -r name executable marker <<<"$prerequisite"
  run_wine "$run_root/prerequisite-$name.log" "$executable"
  grep -q "$marker" "$run_root/prerequisite-$name.log"
  stop_server
  name_upper="$(printf '%s' "$name" | tr '[:lower:]' '[:upper:]')"
  echo "GECKO_PREREQ_I386_${name_upper}_OK"
done

for spec in \
  "i386:$TOOLCHAIN/i686-w64-mingw32-gcc" \
  "x86_64:$TOOLCHAIN/x86_64-w64-mingw32-gcc"; do
  IFS=: read -r arch cc <<<"$spec"
  probe="$run_root/mshtml-$arch.exe"
  "$cc" -O2 -Wall -Wextra -municode "$VKMT/test/browser/mshtml_runtime_probe.c" \
    -o "$probe" -lmshtml -lole32 -loleaut32 -luuid
  if test "$arch" = i386 && test -n "${VKMT_GECKO_I386_WINEDEBUG:-}"; then
    VKMT_RUN_WINEDEBUG="$VKMT_GECKO_I386_WINEDEBUG" \
      run_wine "$run_root/$arch.log" "$probe"
  else
    run_wine "$run_root/$arch.log" "$probe"
  fi
  grep -q MSHTML_RUNTIME_ALL_OK "$run_root/$arch.log"
  stop_server
  arch_upper="$(printf '%s' "$arch" | tr '[:lower:]' '[:upper:]')"
  echo "GECKO_MSHTML_${arch_upper}_OK"
done
echo GECKO_MSHTML_X64_I386_ALL_OK
