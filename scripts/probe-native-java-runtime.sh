#!/bin/bash
# Prove Oracle JRE 8u501 ARM64 and the Wine-prefix-to-native-Java handoff.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
JAVA_HOME="$VKMT/third_party/private/oracle-jre-8u501-arm64/Home"
JAVA="$JAVA_HOME/bin/java"
BUILD="$VKMT/wine/build-ec"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
RUNS="$VKMT/build/probe-runs"
SOURCE="$VKMT/test/java/VkmtNativeJavaProbe.java"
JNI_SOURCE="$VKMT/test/java/native_java_jni.c"

"$VKMT/scripts/stage-native-java-runtime.sh"
ECJ="$("$VKMT/scripts/fetch-java-test-tools.sh")"
test -x "$JAVA"
mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/native-java.XXXXXX")"
prefix="$run_root/prefix"
tls_pid=

cleanup()
{
  status=$?
  if test -n "$tls_pid"; then
    kill "$tls_pid" >/dev/null 2>&1 || true
    wait "$tls_pid" >/dev/null 2>&1 || true
  fi
  WINEPREFIX="$prefix" "$WINESERVER" -k >/dev/null 2>&1 || true
  WINEPREFIX="$prefix" "$WINESERVER" -w >/dev/null 2>&1 || true
  case "$run_root" in
    "$RUNS"/*)
      test "${VKMT_KEEP_PROBE_RUN:-0}" = 1 ||
        /usr/bin/trash "$run_root" >/dev/null 2>&1 || true
      ;;
  esac
  exit "$status"
}
trap cleanup EXIT

classes="$run_root/classes"
mkdir -p "$classes" "$run_root/jar/META-INF"
"$JAVA" -server -jar "$ECJ" -1.8 -proc:none -d "$classes" "$SOURCE"
test -f "$classes/VkmtNativeJavaProbe.class"

install -m 0644 "$classes"/VkmtNativeJavaProbe*.class "$run_root/jar/"
printf 'Manifest-Version: 1.0\r\nMain-Class: VkmtNativeJavaProbe\r\n\r\n' \
  >"$run_root/jar/META-INF/MANIFEST.MF"
(
  cd "$run_root/jar"
  /usr/bin/zip -q -X "$run_root/vkmt-native-java-probe.jar" \
    META-INF/MANIFEST.MF VkmtNativeJavaProbe*.class
)

clang -arch arm64 -O2 -dynamiclib -fvisibility=hidden \
  -install_name @rpath/libvkmt_java_jni.dylib \
  "$JNI_SOURCE" -o "$run_root/libvkmt_java_jni.dylib"
test "$(lipo -archs "$run_root/libvkmt_java_jni.dylib")" = arm64
if otool -L "$run_root/libvkmt_java_jni.dylib" | grep -q '/opt/homebrew'; then
  echo "JNI fixture has a Homebrew dependency" >&2
  exit 1
fi

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

"$JAVA" -server \
  "-Dvkmt.jni=$run_root/libvkmt_java_jni.dylib" \
  "-Dvkmt.tls.url=$tls_url" \
  -cp "$classes" VkmtNativeJavaProbe >"$run_root/class.log" 2>&1
grep -q 'VKMT_NATIVE_JAVA_8U501_SERVER_CLASS_JNI_TLS_OK' "$run_root/class.log"

"$JAVA" -server \
  "-Dvkmt.jni=$run_root/libvkmt_java_jni.dylib" \
  "-Dvkmt.tls.url=$tls_url" \
  -jar "$run_root/vkmt-native-java-probe.jar" >"$run_root/jar.log" 2>&1
grep -q 'VKMT_NATIVE_JAVA_8U501_SERVER_CLASS_JNI_TLS_OK' "$run_root/jar.log"

mkdir -p "$prefix/drive_c/windows/system32" "$prefix/drive_c/vkmt/bin"
for dll in xtajit64 xtajit wow64 wow64win; do
  install -m 0644 "$BUILD/dlls/$dll/aarch64-windows/$dll.dll" \
    "$prefix/drive_c/windows/system32/$dll.dll"
done
"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
gtimeout --signal=TERM --kill-after=10s 120s \
  env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
    WINE_NO_EXPLORER=1 WINEDEBUG=-all MVK_CONFIG_LOG_LEVEL=0 \
    "$WINE" "$WINEBOOT" --init >"$run_root/wineboot.log" 2>&1
WINEPREFIX="$prefix" "$WINESERVER" -k >/dev/null 2>&1 || true
WINEPREFIX="$prefix" "$WINESERVER" -w >/dev/null 2>&1 || true
"$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"
"$VKMT/scripts/stage-native-java-handoff.sh" --prefix "$prefix"

gtimeout --signal=TERM --kill-after=10s 120s \
  env WINEPREFIX="$prefix" WINEBUILDDIR="$BUILD" WINEBOOTSTRAPMODE=1 \
    WINE_NO_EXPLORER=1 WINEDEBUG=-all MVK_CONFIG_LOG_LEVEL=0 \
    VKMT_NATIVE_JAVA="$JAVA" \
    VKMT_NATIVE_JAVA_JAR="$run_root/vkmt-native-java-probe.jar" \
    VKMT_NATIVE_JAVA_JNI="$run_root/libvkmt_java_jni.dylib" \
    VKMT_NATIVE_JAVA_TLS_URL="$tls_url" \
    "$WINE" "$prefix/drive_c/vkmt/bin/vkmt-native-java-handoff.exe" \
    >"$run_root/wine-handoff.log" 2>&1
grep -q 'VKMT_NATIVE_JAVA_8U501_SERVER_CLASS_JNI_TLS_OK' \
  "$run_root/wine-handoff.log"
grep -q 'VKMT_NATIVE_JAVA_WINE_PREFIX_HANDOFF_OK' "$run_root/wine-handoff.log"

WINEPREFIX="$prefix" "$WINESERVER" -k >/dev/null 2>&1 || true
WINEPREFIX="$prefix" "$WINESERVER" -w >/dev/null 2>&1 || true
sed -n '1,80p' "$run_root/class.log"
sed -n '1,80p' "$run_root/jar.log"
sed -n '1,120p' "$run_root/wine-handoff.log"
echo "VKMT_NATIVE_JAVA_8U501_ALL_OK"
