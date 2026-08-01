#!/bin/bash
# Prove matched Windows JNI and Java services under x86_64/i386 -Xint.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${WINEBUILDDIR:-$VKMT/wine/build-ec}"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
RUNS="$VKMT/build/probe-runs"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
JAVA_STAGE="$BUILD/java-runtime"
NATIVE_JAVA="$VKMT/third_party/private/oracle-jre-8u501-arm64/Home/bin/java"
JAVA_SOURCE="$VKMT/test/java/VkmtWindowsJavaServiceProbe.java"
DYNAMIC_SOURCE="$VKMT/test/java/vkmt/dynamic/DynamicPayload.java"
JNI_SOURCE="$VKMT/test/java/windows_java_jni.c"
I386_PROVIDER="${VKMT_XTAJIT_SOURCE:-$VKMT/build/fex-wow64-java-final/provider/xtajit.dll}"
I386_PROVIDER_SHA="${VKMT_XTAJIT_SHA256:-}"
I386_GOLDEN="$VKMT/wine/wine-11.12/runtime-providers/xtajit-arm64-known-good.dll"
I386_GOLDEN_SHA="$(shasum -a 256 "$I386_GOLDEN" | awk '{print $1}')"
X64_GOLDEN="$VKMT/wine/wine-11.12/runtime-providers/xtajit64-arm64ec-known-good.dll"
X64_GOLDEN_SHA="$(shasum -a 256 "$X64_GOLDEN" | awk '{print $1}')"
EVIDENCE="$VKMT/docs/validation/windows-java-j2-20260729"

for required in "$WINE" "$WINESERVER" "$WINEBOOT" "$NATIVE_JAVA" \
    "$JAVA_SOURCE" "$DYNAMIC_SOURCE" "$JNI_SOURCE" "$I386_PROVIDER" \
    "$I386_GOLDEN" "$X64_GOLDEN"; do
  test -e "$required" || {
    echo "Missing Windows Java J2 input: $required" >&2
    exit 1
  }
done
if test -z "$I386_PROVIDER_SHA"; then
  I386_PROVIDER_SHA="$(shasum -a 256 "$I386_PROVIDER" | awk '{print $1}')"
fi
printf '%s  %s\n' "$I386_PROVIDER_SHA" "$I386_PROVIDER" | shasum -a 256 -c -
printf '%s  %s\n' "$I386_GOLDEN_SHA" "$I386_GOLDEN" | shasum -a 256 -c -
printf '%s  %s\n' "$X64_GOLDEN_SHA" "$X64_GOLDEN" | shasum -a 256 -c -

"$VKMT/scripts/stage-windows-java-runtime.sh"
JNI_INCLUDE="$("$VKMT/scripts/fetch-java-jni-headers.sh")"
ECJ="$("$VKMT/scripts/fetch-java-test-tools.sh")"
test -f "$JNI_INCLUDE/jni.h"
test -f "$JNI_INCLUDE/win32/jni_md.h"
test -f "$ECJ"

mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/windows-java.j2.XXXXXX")"
prefix="$run_root/prefix"
wine_pid=
tls_pid=
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=10s "${VKMT_JAVA_J2_TIMEOUT:-240}s")
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=10s "${VKMT_JAVA_J2_TIMEOUT:-240}s")
fi

cleanup()
{
  status=$?
  test -z "$wine_pid" || kill -TERM "$wine_pid" 2>/dev/null || true
  if test -n "$tls_pid"; then
    kill -TERM "$tls_pid" 2>/dev/null || true
    wait "$tls_pid" 2>/dev/null || true
  fi
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  case "$run_root" in
    "$RUNS"/*)
      if test "${VKMT_KEEP_JAVA_J2_RUN:-0}" = 1; then
        echo "Retained Windows Java J2 run: $run_root" >&2
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
    WINEBOOTSTRAPMODE=1 WINE_NO_EXPLORER=1 WINEDEBUG=-all \
    FEX_TSOENABLED=1 MVK_CONFIG_LOG_LEVEL=0 \
    "$WINE" "$@" >"$output" 2>&1 &
  wine_pid=$!
  if wait "$wine_pid"; then result=0; else result=$?; fi
  wine_pid=
  return "$result"
}

classes="$run_root/classes"
jar_tree="$run_root/jar"
mkdir -p "$classes" "$jar_tree/META-INF"
"$NATIVE_JAVA" -server -jar "$ECJ" -1.8 -proc:none -d "$classes" \
  "$JAVA_SOURCE" "$DYNAMIC_SOURCE"
test -f "$classes/VkmtWindowsJavaServiceProbe.class"
test -f "$classes/vkmt/dynamic/DynamicPayload.class"
ditto "$classes" "$jar_tree"
printf 'Manifest-Version: 1.0\r\nMain-Class: VkmtWindowsJavaServiceProbe\r\n\r\n' \
  >"$jar_tree/META-INF/MANIFEST.MF"
(
  cd "$jar_tree"
  /usr/bin/zip -q -X -r "$run_root/vkmt-windows-java-j2.jar" .
)

"$TOOL/x86_64-w64-mingw32-clang" -O2 -Wall -Wextra \
  -Wno-ignored-attributes -shared \
  -I"$JNI_INCLUDE" -I"$JNI_INCLUDE/win32" \
  "$JNI_SOURCE" -o "$run_root/vkmt-java-jni-x86_64.dll"
"$TOOL/i686-w64-mingw32-clang" -O2 -Wall -Wextra \
  -Wno-ignored-attributes -shared \
  -Wl,--kill-at -I"$JNI_INCLUDE" -I"$JNI_INCLUDE/win32" \
  "$JNI_SOURCE" -o "$run_root/vkmt-java-jni-i386.dll"

for spec in \
    "vkmt-java-jni-x86_64.dll:IMAGE_FILE_MACHINE_AMD64" \
    "vkmt-java-jni-i386.dll:IMAGE_FILE_MACHINE_I386"; do
  dll=${spec%%:*}
  expected=${spec#*:}
  machine="$("$TOOL/llvm-readobj" --file-headers "$run_root/$dll" |
    awk '/^[[:space:]]*Machine:/ {print $2; exit}')"
  test "$machine" = "$expected" || {
    echo "Wrong JNI fixture machine: $dll ($machine)" >&2
    exit 1
  }
  "$TOOL/llvm-readobj" --coff-exports "$run_root/$dll" \
    >"$run_root/$dll.exports"
  grep -q 'Name: JNI_OnLoad' "$run_root/$dll.exports"
  grep -q 'Name: Java_VkmtWindowsJavaServiceProbe_nativePointerBits' \
    "$run_root/$dll.exports"
  grep -q 'Name: Java_VkmtWindowsJavaServiceProbe_nativeSecondThread' \
    "$run_root/$dll.exports"
done

port=$((41000 + ($$ % 20000)))
openssl req -x509 -newkey rsa:2048 -sha256 -nodes \
  -keyout "$run_root/tls.key" -out "$run_root/tls.crt" \
  -subj /CN=127.0.0.1 -days 1 >"$run_root/openssl-cert.log" 2>&1
printf 'VKMT_J2_HTTPS_OK\n' >"$run_root/vkmt-j2.txt"
(
  cd "$run_root"
  openssl s_server -quiet -accept "127.0.0.1:$port" \
    -cert tls.crt -key tls.key -WWW
) >"$run_root/tls-server.log" 2>&1 &
tls_pid=$!
for attempt in 1 2 3 4 5; do
  nc -z 127.0.0.1 "$port" >/dev/null 2>&1 && break
  sleep 1
done
nc -z 127.0.0.1 "$port" >/dev/null 2>&1
https_url="https://127.0.0.1:$port/vkmt-j2.txt"

system32="$prefix/drive_c/windows/system32"
syswow64="$prefix/drive_c/windows/syswow64"
probe_dir="$prefix/drive_c/vkmt/probe"
mkdir -p "$system32" "$syswow64" "$probe_dir"
install -m 0644 "$BUILD/dlls/wow64/aarch64-windows/wow64.dll" \
  "$system32/wow64.dll"
install -m 0644 "$BUILD/dlls/wow64win/aarch64-windows/wow64win.dll" \
  "$system32/wow64win.dll"
while IFS= read -r dll; do
  install -m 0644 "$dll" "$syswow64/$(basename "$dll")"
done < <(find "$BUILD/dlls" -type f -path '*/i386-windows/*.dll' -print |
  LC_ALL=C sort)

"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
run_wine "$run_root/wineboot.log" "$WINEBOOT" --init || {
  echo "Windows Java J2 wineboot failed" >&2
  tail -n 160 "$run_root/wineboot.log" >&2
  exit 1
}
VKMT_XTAJIT_SOURCE="$I386_PROVIDER" VKMT_XTAJIT_SHA256="$I386_PROVIDER_SHA" \
  "$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
VKMT_XTAJIT_SOURCE="$I386_PROVIDER" VKMT_XTAJIT_SHA256="$I386_PROVIDER_SHA" \
  "$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"

ditto "$JAVA_STAGE/x86_64" "$prefix/drive_c/vkmt/java-x86_64"
ditto "$JAVA_STAGE/i386" "$prefix/drive_c/vkmt/java-i386"
ditto "$classes" "$probe_dir/classes"
install -m 0644 "$run_root/vkmt-windows-java-j2.jar" \
  "$probe_dir/vkmt-windows-java-j2.jar"
install -m 0644 "$run_root/vkmt-java-jni-x86_64.dll" \
  "$probe_dir/vkmt-java-jni-x86_64.dll"
install -m 0644 "$run_root/vkmt-java-jni-i386.dll" \
  "$probe_dir/vkmt-java-jni-i386.dll"

x64_java="$prefix/drive_c/vkmt/java-x86_64/bin/java.exe"
i386_java="$prefix/drive_c/vkmt/java-i386/bin/java.exe"
classes_win='C:\vkmt\probe\classes'
jar_win='C:\vkmt\probe\vkmt-windows-java-j2.jar'
https_property="-Dvkmt.https.url=$https_url"

# The x86_64 Server interpreter is the control lane and runs first.
run_wine "$run_root/x64.log" "$x64_java" -server -Xint \
  '-Dvkmt.jni=C:\vkmt\probe\vkmt-java-jni-x86_64.dll' \
  '-Dvkmt.work=C:\vkmt\probe\work-x86_64' \
  "-Dvkmt.probe.jar=$jar_win" \
  '-Dvkmt.java.exe=C:\vkmt\java-x86_64\bin\java.exe' \
  "-Dvkmt.classpath=$classes_win" "$https_property" \
  '-Dvkmt.hook=C:\vkmt\probe\x64-shutdown.marker' \
  -cp "$classes_win" VkmtWindowsJavaServiceProbe 64 Server || {
    echo "Windows Java J2 x86_64 services failed" >&2
    tail -n 200 "$run_root/x64.log" >&2
    exit 1
  }
grep -Fq 'VKMT_WINDOWS_JAVA_J2_OK model=64' "$run_root/x64.log"
grep -Fq 'pointerBits=64' "$run_root/x64.log"
grep -Fq 'classLoads=32 thread=VKMT_J2_TLS_OK' "$run_root/x64.log"
grep -Fq 'process=VKMT_J2_PROCESS_OK socket=VKMT_J2_SOCKET_OK https=VKMT_J2_HTTPS_OK' \
  "$run_root/x64.log"
grep -Fq 'VKMT_J2_SHUTDOWN_HOOK_OK' \
  "$probe_dir/x64-shutdown.marker"
test ! -e "$probe_dir/work-x86_64/mapped.bin"

# The i386 Client interpreter uses the J0 software-TSO candidate.
run_wine "$run_root/i386.log" "$i386_java" -client -Xint \
  '-Dvkmt.jni=C:\vkmt\probe\vkmt-java-jni-i386.dll' \
  '-Dvkmt.work=C:\vkmt\probe\work-i386' \
  "-Dvkmt.probe.jar=$jar_win" \
  '-Dvkmt.java.exe=C:\vkmt\java-i386\bin\java.exe' \
  "-Dvkmt.classpath=$classes_win" "$https_property" \
  '-Dvkmt.hook=C:\vkmt\probe\i386-shutdown.marker' \
  -cp "$classes_win" VkmtWindowsJavaServiceProbe 32 Client || {
    echo "Windows Java J2 i386 services failed" >&2
    tail -n 240 "$run_root/i386.log" >&2
    exit 1
  }
grep -Fq 'VKMT_WINDOWS_JAVA_J2_OK model=32' "$run_root/i386.log"
grep -Fq 'pointerBits=32' "$run_root/i386.log"
grep -Fq 'classLoads=32 thread=VKMT_J2_TLS_OK' "$run_root/i386.log"
grep -Fq 'process=VKMT_J2_PROCESS_OK socket=VKMT_J2_SOCKET_OK https=VKMT_J2_HTTPS_OK' \
  "$run_root/i386.log"
grep -Fq 'VKMT_J2_SHUTDOWN_HOOK_OK' \
  "$probe_dir/i386-shutdown.marker"
test ! -e "$probe_dir/work-i386/mapped.bin"

WINEPREFIX="$prefix" "$WINESERVER" -k
WINEPREFIX="$prefix" "$WINESERVER" -w
if pgrep -alf 'java(-x86_64|-i386)?[/\\\\]bin[/\\\\]java.exe' \
    >"$run_root/retained-java.txt"; then
  echo "Windows Java J2 retained a JVM process" >&2
  cat "$run_root/retained-java.txt" >&2
  exit 1
fi

mkdir -p "$EVIDENCE"
{
  printf 'candidate_sha256=%s\n' "$I386_PROVIDER_SHA"
  printf 'golden_i386_sha256=%s\n' "$I386_GOLDEN_SHA"
  printf 'golden_x86_64_sha256=%s\n' "$X64_GOLDEN_SHA"
  printf 'jni_h_sha256=%s\n' \
    "$(shasum -a 256 "$JNI_INCLUDE/jni.h" | awk '{print $1}')"
  printf 'jni_md_h_sha256=%s\n' \
    "$(shasum -a 256 "$JNI_INCLUDE/win32/jni_md.h" | awk '{print $1}')"
  printf 'jni_x86_64_sha256=%s\n' \
    "$(shasum -a 256 "$run_root/vkmt-java-jni-x86_64.dll" | awk '{print $1}')"
  printf 'jni_i386_sha256=%s\n' \
    "$(shasum -a 256 "$run_root/vkmt-java-jni-i386.dll" | awk '{print $1}')"
  grep -F 'VKMT_WINDOWS_JAVA_J2_OK' "$run_root/x64.log"
  grep -F 'VKMT_WINDOWS_JAVA_J2_OK' "$run_root/i386.log"
  printf 'x86_64_shutdown_hook=1\n'
  printf 'i386_shutdown_hook=1\n'
  printf 'exact_shutdown=1\n'
} >"$EVIDENCE/RESULTS.txt"
install -m 0644 "$run_root/vkmt-java-jni-x86_64.dll.exports" \
  "$EVIDENCE/jni-x86_64-exports.txt"
install -m 0644 "$run_root/vkmt-java-jni-i386.dll.exports" \
  "$EVIDENCE/jni-i386-exports.txt"

printf '%s  %s\n' "$I386_GOLDEN_SHA" "$I386_GOLDEN" | shasum -a 256 -c -
printf '%s  %s\n' "$X64_GOLDEN_SHA" "$X64_GOLDEN" | shasum -a 256 -c -
printf '%s  %s\n' "$I386_GOLDEN_SHA" \
  "$BUILD/dlls/xtajit/aarch64-windows/xtajit.dll" | shasum -a 256 -c -
printf '%s  %s\n' "$X64_GOLDEN_SHA" \
  "$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll" | shasum -a 256 -c -

echo "VKMT_WINDOWS_JAVA_J2_SERVICES_OK"
