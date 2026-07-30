#!/bin/bash
# Prove native, x86_64, and i386 Java plus all Wine guest ABIs in one prefix.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${WINEBUILDDIR:-$VKMT/wine/build-ec}"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
RUNS="$VKMT/build/probe-runs"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
NATIVE_JAVA="$VKMT/third_party/private/oracle-jre-8u501-arm64/Home/bin/java"
JAVA_STAGE="$BUILD/java-runtime"
I386_PROVIDER="${VKMT_XTAJIT_SOURCE:-$VKMT/wine/wine-11.12/runtime-providers/xtajit-arm64-known-good.dll}"
I386_PROVIDER_SHA="${VKMT_XTAJIT_SHA256:-fe1345724f6a2950541966515f766099b7bce38701c9960d4be513c27ec81073}"
X64_PROVIDER="${VKMT_XTAJIT64_SOURCE:-$VKMT/wine/wine-11.12/runtime-providers/xtajit64-arm64ec-known-good.dll}"
X64_PROVIDER_SHA="${VKMT_XTAJIT64_SHA256:-7b9f55ceabe971ffa1f514570bb54ed7b5640959e4440e7f8a013e9af13ab7e6}"
EVIDENCE="$VKMT/docs/validation/windows-java-j6-20260729"

for required in "$WINE" "$WINESERVER" "$WINEBOOT" "$NATIVE_JAVA" \
    "$I386_PROVIDER" "$X64_PROVIDER" \
    "$VKMT/test/java/VkmtNativeJavaProbe.java" \
    "$VKMT/test/java/native_java_jni.c" \
    "$VKMT/test/java/VkmtWindowsJavaInterpreterProbe.java" \
    "$VKMT/test/java/vkmt/dynamic/DynamicPayload.java" \
    "$VKMT/test/aarch64_smoke.c" "$VKMT/test/x64emu/hello_ec.c" \
    "$VKMT/test/x64emu/entry_x64.c" "$VKMT/test/i386_smoke.c"; do
  test -e "$required" || {
    echo "Missing Windows Java J6 input: $required" >&2
    exit 1
  }
done
printf '%s  %s\n' "$I386_PROVIDER_SHA" "$I386_PROVIDER" | shasum -a 256 -c -
printf '%s  %s\n' "$X64_PROVIDER_SHA" "$X64_PROVIDER" | shasum -a 256 -c -

for macho in "$WINE" "$WINESERVER" "$BUILD/dlls/ntdll/ntdll.so" "$NATIVE_JAVA"; do
  test "$(/usr/bin/lipo -archs "$macho")" = arm64 || {
    echo "Non-ARM64 host artifact: $macho" >&2
    exit 1
  }
done
if translated="$(/usr/sbin/sysctl -in sysctl.proc_translated 2>/dev/null)"; then
  test "$translated" = 0 || { echo "J6 runner is under Rosetta" >&2; exit 1; }
fi

"$VKMT/scripts/stage-native-java-runtime.sh"
"$VKMT/scripts/stage-windows-java-runtime.sh"
ECJ="$("$VKMT/scripts/fetch-java-test-tools.sh")"
test -f "$ECJ"

mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/windows-java.j6.XXXXXX")"
prefix="$run_root/prefix"
wine_pid=
tls_pid=
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=10s \
    "${VKMT_JAVA_J6_TIMEOUT:-180}s")
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=10s \
    "${VKMT_JAVA_J6_TIMEOUT:-180}s")
fi

cleanup()
{
  status=$?
  test -z "$wine_pid" || kill -TERM "$wine_pid" 2>/dev/null || true
  if test -n "$tls_pid"; then
    kill "$tls_pid" 2>/dev/null || true
    wait "$tls_pid" 2>/dev/null || true
  fi
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  case "$run_root" in
    "$RUNS"/*)
      if test "${VKMT_KEEP_JAVA_J6_RUN:-0}" = 1; then
        echo "Retained Windows Java J6 run: $run_root" >&2
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
    WINEBOOTSTRAPMODE=1 WINE_NO_EXPLORER=1 WINEDEBUG=-all \
    FEX_TSOENABLED=1 FEX_SILENTLOG=1 VKMT_X64_TIER0=0 \
    MVK_CONFIG_LOG_LEVEL=0 "$WINE" "$@" >"$output" 2>&1 &
  wine_pid=$!
  if wait "$wine_pid"; then code=0; else code=$?; fi
  wine_pid=
  return "$code"
}

native_classes="$run_root/native-classes"
native_jar_tree="$run_root/native-jar"
windows_classes="$run_root/windows-classes"
windows_jar_tree="$run_root/windows-jar"
mkdir -p "$native_classes" "$native_jar_tree/META-INF" \
  "$windows_classes" "$windows_jar_tree/META-INF" "$windows_jar_tree/vkmt"

"$NATIVE_JAVA" -server -jar "$ECJ" -1.8 -proc:none -d "$native_classes" \
  "$VKMT/test/java/VkmtNativeJavaProbe.java"
install -m 0644 "$native_classes"/VkmtNativeJavaProbe*.class "$native_jar_tree/"
printf 'Manifest-Version: 1.0\r\nMain-Class: VkmtNativeJavaProbe\r\n\r\n' \
  >"$native_jar_tree/META-INF/MANIFEST.MF"
(
  cd "$native_jar_tree"
  /usr/bin/zip -q -X "$run_root/vkmt-native-java-probe.jar" \
    META-INF/MANIFEST.MF VkmtNativeJavaProbe*.class
)
clang -arch arm64 -O2 -dynamiclib -fvisibility=hidden \
  -install_name @rpath/libvkmt_java_jni.dylib \
  "$VKMT/test/java/native_java_jni.c" \
  -o "$run_root/libvkmt_java_jni.dylib"
test "$(/usr/bin/lipo -archs "$run_root/libvkmt_java_jni.dylib")" = arm64

"$NATIVE_JAVA" -server -jar "$ECJ" -1.8 -proc:none -d "$windows_classes" \
  "$VKMT/test/java/VkmtWindowsJavaInterpreterProbe.java" \
  "$VKMT/test/java/vkmt/dynamic/DynamicPayload.java"
ditto "$windows_classes" "$windows_jar_tree"
printf 'VKMT_J1_ZIP_OK\n' >"$windows_jar_tree/vkmt/payload.txt"
printf 'Manifest-Version: 1.0\r\nMain-Class: VkmtWindowsJavaInterpreterProbe\r\n\r\n' \
  >"$windows_jar_tree/META-INF/MANIFEST.MF"
(
  cd "$windows_jar_tree"
  /usr/bin/zip -q -X -r "$run_root/vkmt-windows-java-j6.jar" .
)

"$TOOL/aarch64-w64-mingw32-clang" -O2 -ffixed-x18 -ffixed-x28 \
  "$VKMT/test/aarch64_smoke.c" -o "$run_root/arm64.exe"
"$TOOL/arm64ec-w64-mingw32-clang" -O2 -ffixed-x18 -ffixed-x28 \
  "$VKMT/test/x64emu/hello_ec.c" -o "$run_root/arm64ec.exe"
"$TOOL/x86_64-w64-mingw32-clang" -O2 \
  "$VKMT/test/x64emu/entry_x64.c" -o "$run_root/x86_64.exe"
"$TOOL/i686-w64-mingw32-clang" -O2 \
  "$VKMT/test/i386_smoke.c" -o "$run_root/i386.exe"

for spec in \
    "arm64.exe:IMAGE_FILE_MACHINE_ARM64" \
    "arm64ec.exe:IMAGE_FILE_MACHINE_ARM64EC" \
    "x86_64.exe:IMAGE_FILE_MACHINE_AMD64" \
    "i386.exe:IMAGE_FILE_MACHINE_I386"; do
  file=${spec%%:*}
  expected=${spec#*:}
  machine="$("$TOOL/llvm-readobj" --file-headers "$run_root/$file" |
    awk '/Machine:/ {print $2; exit}')"
  test "$machine" = "$expected"
done

port=$((40000 + ($$ % 20000)))
openssl req -x509 -newkey rsa:2048 -sha256 -nodes \
  -keyout "$run_root/tls.key" -out "$run_root/tls.crt" \
  -subj /CN=127.0.0.1 -days 1 >"$run_root/openssl-cert.log" 2>&1
printf 'VKMT_TLS_SERVER_OK\n' >"$run_root/vkmt.txt"
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
tls_url="https://127.0.0.1:$port/vkmt.txt"

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

VKMT_XTAJIT_SOURCE="$I386_PROVIDER" VKMT_XTAJIT_SHA256="$I386_PROVIDER_SHA" \
VKMT_XTAJIT64_SOURCE="$X64_PROVIDER" VKMT_XTAJIT64_SHA256="$X64_PROVIDER_SHA" \
  "$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
run_wine "$run_root/wineboot.log" "$WINEBOOT" --init || {
  echo "Windows Java J6 wineboot failed" >&2
  tail -n 180 "$run_root/wineboot.log" >&2
  exit 1
}
VKMT_XTAJIT_SOURCE="$I386_PROVIDER" VKMT_XTAJIT_SHA256="$I386_PROVIDER_SHA" \
VKMT_XTAJIT64_SOURCE="$X64_PROVIDER" VKMT_XTAJIT64_SHA256="$X64_PROVIDER_SHA" \
  "$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
VKMT_XTAJIT_SOURCE="$I386_PROVIDER" VKMT_XTAJIT_SHA256="$I386_PROVIDER_SHA" \
VKMT_XTAJIT64_SOURCE="$X64_PROVIDER" VKMT_XTAJIT64_SHA256="$X64_PROVIDER_SHA" \
  "$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"

"$VKMT/scripts/stage-native-java-handoff.sh" --prefix "$prefix"
ditto "$JAVA_STAGE/x86_64" "$prefix/drive_c/vkmt/java-x86_64"
ditto "$JAVA_STAGE/i386" "$prefix/drive_c/vkmt/java-i386"
ditto "$windows_classes" "$probe_dir/classes"
install -m 0644 "$run_root/vkmt-windows-java-j6.jar" \
  "$probe_dir/vkmt-windows-java-j6.jar"

VKMT_NATIVE_JAVA="$NATIVE_JAVA" \
VKMT_NATIVE_JAVA_JAR="$run_root/vkmt-native-java-probe.jar" \
VKMT_NATIVE_JAVA_JNI="$run_root/libvkmt_java_jni.dylib" \
VKMT_NATIVE_JAVA_TLS_URL="$tls_url" \
run_wine "$run_root/native-java.log" \
  "$prefix/drive_c/vkmt/bin/vkmt-native-java-handoff.exe" || {
    tail -n 160 "$run_root/native-java.log" >&2
    exit 1
  }
grep -q 'VKMT_NATIVE_JAVA_8U501_SERVER_CLASS_JNI_TLS_OK' \
  "$run_root/native-java.log"
grep -q 'VKMT_NATIVE_JAVA_WINE_PREFIX_HANDOFF_OK' "$run_root/native-java.log"
echo J6_NATIVE_ARM64_ORACLE_SERVER_OK

jar_win='C:\vkmt\probe\vkmt-windows-java-j6.jar'
x64_java="$prefix/drive_c/vkmt/java-x86_64/bin/java.exe"
i386_java="$prefix/drive_c/vkmt/java-i386/bin/java.exe"
run_wine "$run_root/x86_64-java.log" "$x64_java" -server \
  "-Dvkmt.probe.jar=$jar_win" -jar "$jar_win" jar 64 Server || {
    echo "J6 Windows x86_64 Server VM failed" >&2
    tail -n 200 "$run_root/x86_64-java.log" >&2
    exit 1
  }
grep -q 'VKMT_WINDOWS_JAVA_J1_OK mode=jar model=64' \
  "$run_root/x86_64-java.log"
echo J6_WINDOWS_X86_64_SERVER_OK

run_wine "$run_root/i386-java.log" "$i386_java" -client \
  "-Dvkmt.probe.jar=$jar_win" -jar "$jar_win" jar 32 Client || {
    echo "J6 Windows i386 Client VM failed" >&2
    tail -n 200 "$run_root/i386-java.log" >&2
    exit 1
  }
grep -q 'VKMT_WINDOWS_JAVA_J1_OK mode=jar model=32' "$run_root/i386-java.log"
echo J6_WINDOWS_I386_CLIENT_OK

run_wine "$run_root/arm64.log" "$run_root/arm64.exe"
grep -q 'VKMT native AArch64 smoke passed' "$run_root/arm64.log"
echo J6_SINGLE_PREFIX_ARM64_OK

if run_wine "$run_root/arm64ec.log" "$run_root/arm64ec.exe"; then
  code=0
else
  code=$?
fi
test "$code" = 42
grep -q 'hello from arm64ec' "$run_root/arm64ec.log"
echo J6_SINGLE_PREFIX_ARM64EC_OK

if run_wine "$run_root/x86_64.log" "$run_root/x86_64.exe"; then
  code=0
else
  code=$?
fi
test "$code" = 7
grep -q 'VKMT entry_x64: hello from x86-64 guest' "$run_root/x86_64.log"
echo J6_SINGLE_PREFIX_X86_64_OK

run_wine "$run_root/i386.log" "$run_root/i386.exe" "Z:$run_root/i386.marker"
for attempt in $(seq 1 60); do
  test -f "$run_root/i386.marker" && break
  sleep 1
done
grep -q 'VKMT i386 WoW64 execution contract passed' "$run_root/i386.marker"
echo J6_SINGLE_PREFIX_I386_OK

WINEPREFIX="$prefix" "$WINESERVER" -k
WINEPREFIX="$prefix" "$WINESERVER" -w
if pgrep -alf 'java(-x86_64|-i386)?[/\\]bin[/\\]java.exe' \
    >"$run_root/retained-java.txt"; then
  echo "J6 retained a Windows JVM process" >&2
  cat "$run_root/retained-java.txt" >&2
  exit 1
fi

find "$EVIDENCE" -depth -delete 2>/dev/null || true
mkdir -p "$EVIDENCE"
{
  printf 'i386_provider_sha256=%s\n' "$I386_PROVIDER_SHA"
  printf 'x86_64_provider_sha256=%s\n' "$X64_PROVIDER_SHA"
  printf 'wow64_sha256=%s\n' \
    "$(shasum -a 256 "$BUILD/dlls/wow64/aarch64-windows/wow64.dll" |
      awk '{print $1}')"
  printf 'prefix_order=native-arm64-java,x86_64-java,i386-java,arm64,arm64ec,x86_64,i386\n'
  grep -F 'VKMT_NATIVE_JAVA_8U501_SERVER_CLASS_JNI_TLS_OK' \
    "$run_root/native-java.log"
  grep -F 'VKMT_NATIVE_JAVA_WINE_PREFIX_HANDOFF_OK' "$run_root/native-java.log"
  grep -F 'VKMT_WINDOWS_JAVA_J1_OK' "$run_root/x86_64-java.log"
  grep -F 'VKMT_WINDOWS_JAVA_J1_OK' "$run_root/i386-java.log"
  printf 'J6_SINGLE_PREFIX_ARM64_OK\n'
  printf 'J6_SINGLE_PREFIX_ARM64EC_OK\n'
  printf 'J6_SINGLE_PREFIX_X86_64_OK\n'
  printf 'J6_SINGLE_PREFIX_I386_OK\n'
  printf 'exact_shutdown=1\n'
} >"$EVIDENCE/RESULTS.txt"
install -m 0644 "$run_root/native-java.log" "$EVIDENCE/"
install -m 0644 "$run_root/x86_64-java.log" "$EVIDENCE/"
install -m 0644 "$run_root/i386-java.log" "$EVIDENCE/"

echo VKMT_WINDOWS_JAVA_J6_UNIFIED_OK
