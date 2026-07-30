#!/bin/bash
# Prove Windows x86_64 Server and i386 Client HotSpot interpreters in one prefix.
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
SOURCE="$VKMT/test/java/VkmtWindowsJavaInterpreterProbe.java"
DYNAMIC_SOURCE="$VKMT/test/java/vkmt/dynamic/DynamicPayload.java"
I386_PROVIDER="${VKMT_XTAJIT_SOURCE:-$VKMT/build/fex-wow64-java-final/provider/xtajit.dll}"
I386_PROVIDER_SHA="${VKMT_XTAJIT_SHA256:-}"
I386_GOLDEN="$VKMT/wine/wine-11.12/runtime-providers/xtajit-arm64-known-good.dll"
I386_GOLDEN_SHA=fe1345724f6a2950541966515f766099b7bce38701c9960d4be513c27ec81073
X64_GOLDEN="$VKMT/wine/wine-11.12/runtime-providers/xtajit64-arm64ec-known-good.dll"
X64_GOLDEN_SHA=7b9f55ceabe971ffa1f514570bb54ed7b5640959e4440e7f8a013e9af13ab7e6
EVIDENCE="$VKMT/docs/validation/windows-java-j1-20260729"

for required in "$WINE" "$WINESERVER" "$WINEBOOT" "$NATIVE_JAVA" \
    "$SOURCE" "$DYNAMIC_SOURCE" "$I386_PROVIDER" "$I386_GOLDEN" \
    "$X64_GOLDEN"; do
  test -e "$required" || {
    echo "Missing Windows Java J1 input: $required" >&2
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
ECJ="$("$VKMT/scripts/fetch-java-test-tools.sh")"
test -f "$ECJ"
mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/windows-java.j1.XXXXXX")"
prefix="$run_root/prefix"
wine_pid=
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=10s "${VKMT_JAVA_J1_TIMEOUT:-120}s")
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=10s "${VKMT_JAVA_J1_TIMEOUT:-120}s")
fi

cleanup()
{
  status=$?
  test -z "$wine_pid" || kill -TERM "$wine_pid" 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  case "$run_root" in
    "$RUNS"/*)
      if test "${VKMT_KEEP_JAVA_J1_RUN:-0}" = 1; then
        echo "Retained Windows Java J1 run: $run_root" >&2
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
    MVK_CONFIG_LOG_LEVEL=0 "$WINE" "$@" >"$output" 2>&1 &
  wine_pid=$!
  if wait "$wine_pid"; then result=0; else result=$?; fi
  wine_pid=
  return "$result"
}

classes="$run_root/classes"
jar_tree="$run_root/jar"
mkdir -p "$classes" "$jar_tree/META-INF" "$jar_tree/vkmt"
"$NATIVE_JAVA" -server -jar "$ECJ" -1.8 -proc:none -d "$classes" \
  "$SOURCE" "$DYNAMIC_SOURCE"
test -f "$classes/VkmtWindowsJavaInterpreterProbe.class"
test -f "$classes/vkmt/dynamic/DynamicPayload.class"
ditto "$classes" "$jar_tree"
printf 'VKMT_J1_ZIP_OK\n' >"$jar_tree/vkmt/payload.txt"
printf 'Manifest-Version: 1.0\r\nMain-Class: VkmtWindowsJavaInterpreterProbe\r\n\r\n' \
  >"$jar_tree/META-INF/MANIFEST.MF"
(
  cd "$jar_tree"
  /usr/bin/zip -q -X -r "$run_root/vkmt-windows-java-j1.jar" .
)

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
  echo "Windows Java J1 wineboot failed" >&2
  tail -n 160 "$run_root/wineboot.log" >&2
  exit 1
}

# Wineboot refreshes system32. Select the J0-proven i386 candidate only now.
VKMT_XTAJIT_SOURCE="$I386_PROVIDER" VKMT_XTAJIT_SHA256="$I386_PROVIDER_SHA" \
  "$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
VKMT_XTAJIT_SOURCE="$I386_PROVIDER" VKMT_XTAJIT_SHA256="$I386_PROVIDER_SHA" \
  "$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"

ditto "$JAVA_STAGE/x86_64" "$prefix/drive_c/vkmt/java-x86_64"
ditto "$JAVA_STAGE/i386" "$prefix/drive_c/vkmt/java-i386"
ditto "$classes" "$probe_dir/classes"
install -m 0644 "$run_root/vkmt-windows-java-j1.jar" \
  "$probe_dir/vkmt-windows-java-j1.jar"

i386_fixture="$run_root/java_tso_preflight.exe"
"$TOOL/i686-w64-mingw32-clang" -O1 -g -Wall -Wextra \
  -Wl,--stack,0x1000000 "$VKMT/test/i386/java_tso_preflight.c" \
  -o "$i386_fixture"
test "$("$TOOL/llvm-readobj" --file-headers "$i386_fixture" |
  awk '/^[[:space:]]*Machine:/ {print $2; exit}')" = IMAGE_FILE_MACHINE_I386
run_wine "$run_root/i386-preflight.log" "$i386_fixture" \
  'C:\vkmt\probe\i386-preflight.marker'
grep -q 'JAVA_TSO_PREFLIGHT_OK' \
  "$prefix/drive_c/vkmt/probe/i386-preflight.marker"

x64_java="$prefix/drive_c/vkmt/java-x86_64/bin/java.exe"
i386_java="$prefix/drive_c/vkmt/java-i386/bin/java.exe"
jar_win='C:\vkmt\probe\vkmt-windows-java-j1.jar'
classes_win='C:\vkmt\probe\classes'

# x86_64 is the control lane and always runs first.
run_wine "$run_root/x64-version.log" "$x64_java" -version
grep -Fq '1.8.0_492' "$run_root/x64-version.log"
grep -Fq '64-Bit Server VM' "$run_root/x64-version.log"
run_wine "$run_root/x64-xint-version.log" "$x64_java" -server -Xint -version
grep -Fq '64-Bit Server VM' "$run_root/x64-xint-version.log"
run_wine "$run_root/x64-classpath.log" "$x64_java" -server -Xint \
  "-Dvkmt.probe.jar=$jar_win" -cp "$classes_win" \
  VkmtWindowsJavaInterpreterProbe classpath 64 Server
grep -Fq 'VKMT_WINDOWS_JAVA_J1_OK mode=classpath model=64' \
  "$run_root/x64-classpath.log"
grep -Fq 'dynamic=VKMT_J1_REFLECTION_OK zip=VKMT_J1_ZIP_OK' \
  "$run_root/x64-classpath.log"
run_wine "$run_root/x64-jar.log" "$x64_java" -server -Xint \
  "-Dvkmt.probe.jar=$jar_win" -jar "$jar_win" jar 64 Server
grep -Fq 'VKMT_WINDOWS_JAVA_J1_OK mode=jar model=64' \
  "$run_root/x64-jar.log"

# The i386 Client VM uses the J0 software-TSO provider in the same prefix.
run_wine "$run_root/i386-version.log" "$i386_java" -version
grep -Fq '1.8.0_472' "$run_root/i386-version.log"
grep -Fq 'Client VM' "$run_root/i386-version.log"
run_wine "$run_root/i386-xint-version.log" "$i386_java" -client -Xint -version
grep -Fq 'Client VM' "$run_root/i386-xint-version.log"
run_wine "$run_root/i386-classpath.log" "$i386_java" -client -Xint \
  "-Dvkmt.probe.jar=$jar_win" -cp "$classes_win" \
  VkmtWindowsJavaInterpreterProbe classpath 32 Client
grep -Fq 'VKMT_WINDOWS_JAVA_J1_OK mode=classpath model=32' \
  "$run_root/i386-classpath.log"
grep -Fq 'dynamic=VKMT_J1_REFLECTION_OK zip=VKMT_J1_ZIP_OK' \
  "$run_root/i386-classpath.log"
run_wine "$run_root/i386-jar.log" "$i386_java" -client -Xint \
  "-Dvkmt.probe.jar=$jar_win" -jar "$jar_win" jar 32 Client
grep -Fq 'VKMT_WINDOWS_JAVA_J1_OK mode=jar model=32' \
  "$run_root/i386-jar.log"

WINEPREFIX="$prefix" "$WINESERVER" -k
WINEPREFIX="$prefix" "$WINESERVER" -w
if pgrep -alf 'java(-x86_64|-i386)?[/\\\\]bin[/\\\\]java.exe' \
    >"$run_root/retained-java.txt"; then
  echo "Windows Java J1 retained a JVM process" >&2
  cat "$run_root/retained-java.txt" >&2
  exit 1
fi

mkdir -p "$EVIDENCE"
{
  printf 'candidate_sha256=%s\n' "$I386_PROVIDER_SHA"
  printf 'golden_i386_sha256=%s\n' "$I386_GOLDEN_SHA"
  printf 'golden_x86_64_sha256=%s\n' "$X64_GOLDEN_SHA"
  printf 'prefix_order=x86_64,i386\n'
  cat "$prefix/drive_c/vkmt/probe/i386-preflight.marker"
  grep -F 'VKMT_WINDOWS_JAVA_J1_OK' "$run_root/x64-classpath.log"
  grep -F 'VKMT_WINDOWS_JAVA_J1_OK' "$run_root/x64-jar.log"
  grep -F 'VKMT_WINDOWS_JAVA_J1_OK' "$run_root/i386-classpath.log"
  grep -F 'VKMT_WINDOWS_JAVA_J1_OK' "$run_root/i386-jar.log"
  printf 'x86_64_interpreter=-server -Xint\n'
  printf 'i386_interpreter=-client -Xint\n'
  printf 'exact_shutdown=1\n'
} >"$EVIDENCE/RESULTS.txt"
install -m 0644 "$run_root/x64-version.log" "$EVIDENCE/x64-version.log"
install -m 0644 "$run_root/i386-version.log" "$EVIDENCE/i386-version.log"
install -m 0644 "$run_root/x64-xint-version.log" \
  "$EVIDENCE/x64-xint-version.log"
install -m 0644 "$run_root/i386-xint-version.log" \
  "$EVIDENCE/i386-xint-version.log"

printf '%s  %s\n' "$I386_GOLDEN_SHA" "$I386_GOLDEN" | shasum -a 256 -c -
printf '%s  %s\n' "$X64_GOLDEN_SHA" "$X64_GOLDEN" | shasum -a 256 -c -
printf '%s  %s\n' "$I386_GOLDEN_SHA" \
  "$BUILD/dlls/xtajit/aarch64-windows/xtajit.dll" | shasum -a 256 -c -
printf '%s  %s\n' "$X64_GOLDEN_SHA" \
  "$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll" | shasum -a 256 -c -

echo "VKMT_WINDOWS_JAVA_J1_INTERPRETERS_OK"
