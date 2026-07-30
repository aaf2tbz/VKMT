#!/bin/bash
# Prove Windows x86_64 Server and i386 Client HotSpot JIT/executable memory.
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
JAVA_SOURCE="$VKMT/test/java/VkmtWindowsJavaJitProbe.java"
DYNAMIC_SOURCE="$VKMT/test/java/vkmt/dynamic/JitPayload.java"
JNI_SOURCE="$VKMT/test/java/windows_java_jit_execmem.c"
I386_PROVIDER="${VKMT_XTAJIT_SOURCE:-$VKMT/build/fex-wow64-java-final/provider/xtajit.dll}"
I386_PROVIDER_SHA="${VKMT_XTAJIT_SHA256:-}"
X64_PROVIDER="${VKMT_XTAJIT64_SOURCE:-$VKMT/build/xtajit64-java-j3-final/provider/xtajit64.dll}"
X64_PROVIDER_SHA="${VKMT_XTAJIT64_SHA256:-}"
I386_GOLDEN="$VKMT/wine/wine-11.12/runtime-providers/xtajit-arm64-known-good.dll"
I386_GOLDEN_SHA=fe1345724f6a2950541966515f766099b7bce38701c9960d4be513c27ec81073
X64_GOLDEN="$VKMT/wine/wine-11.12/runtime-providers/xtajit64-arm64ec-known-good.dll"
X64_GOLDEN_SHA=7b9f55ceabe971ffa1f514570bb54ed7b5640959e4440e7f8a013e9af13ab7e6
EVIDENCE="$VKMT/docs/validation/windows-java-j3-20260729"

for required in "$WINE" "$WINESERVER" "$WINEBOOT" "$NATIVE_JAVA" \
    "$JAVA_SOURCE" "$DYNAMIC_SOURCE" "$JNI_SOURCE" "$I386_PROVIDER" \
    "$X64_PROVIDER" "$I386_GOLDEN" "$X64_GOLDEN"; do
  test -e "$required" || {
    echo "Missing Windows Java J3 input: $required" >&2
    exit 1
  }
done
if test -z "$I386_PROVIDER_SHA"; then
  I386_PROVIDER_SHA="$(shasum -a 256 "$I386_PROVIDER" | awk '{print $1}')"
fi
if test -z "$X64_PROVIDER_SHA"; then
  X64_PROVIDER_SHA="$(shasum -a 256 "$X64_PROVIDER" | awk '{print $1}')"
fi
printf '%s  %s\n' "$I386_PROVIDER_SHA" "$I386_PROVIDER" | shasum -a 256 -c -
printf '%s  %s\n' "$X64_PROVIDER_SHA" "$X64_PROVIDER" | shasum -a 256 -c -
printf '%s  %s\n' "$I386_GOLDEN_SHA" "$I386_GOLDEN" | shasum -a 256 -c -
printf '%s  %s\n' "$X64_GOLDEN_SHA" "$X64_GOLDEN" | shasum -a 256 -c -

"$VKMT/scripts/stage-windows-java-runtime.sh"
JNI_INCLUDE="$("$VKMT/scripts/fetch-java-jni-headers.sh")"
ECJ="$("$VKMT/scripts/fetch-java-test-tools.sh")"
test -f "$JNI_INCLUDE/jni.h"
test -f "$JNI_INCLUDE/win32/jni_md.h"
test -f "$ECJ"

mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/windows-java.j3.XXXXXX")"
prefix="$run_root/prefix"
wine_pid=
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=10s "${VKMT_JAVA_J3_TIMEOUT:-360}s")
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=10s "${VKMT_JAVA_J3_TIMEOUT:-360}s")
fi

cleanup()
{
  status=$?
  test -z "$wine_pid" || kill -TERM "$wine_pid" 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  case "$run_root" in
    "$RUNS"/*)
      if test "${VKMT_KEEP_JAVA_J3_RUN:-0}" = 1; then
        echo "Retained Windows Java J3 run: $run_root" >&2
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
    FEX_TSOENABLED=1 VKMT_X64_TIER0="${VKMT_X64_TIER0:-0}" \
    MVK_CONFIG_LOG_LEVEL=0 \
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
test -f "$classes/VkmtWindowsJavaJitProbe.class"
test -f "$classes/vkmt/dynamic/JitPayload.class"
ditto "$classes" "$jar_tree"
printf 'Manifest-Version: 1.0\r\nMain-Class: VkmtWindowsJavaJitProbe\r\n\r\n' \
  >"$jar_tree/META-INF/MANIFEST.MF"
(
  cd "$jar_tree"
  /usr/bin/zip -q -X -r "$run_root/vkmt-windows-java-j3.jar" .
)

"$TOOL/x86_64-w64-mingw32-clang" -O2 -Wall -Wextra \
  -Wno-ignored-attributes -shared \
  -I"$JNI_INCLUDE" -I"$JNI_INCLUDE/win32" "$JNI_SOURCE" \
  -o "$run_root/vkmt-java-jit-x86_64.dll"
"$TOOL/i686-w64-mingw32-clang" -O2 -Wall -Wextra \
  -Wno-ignored-attributes -shared -Wl,--kill-at \
  -I"$JNI_INCLUDE" -I"$JNI_INCLUDE/win32" "$JNI_SOURCE" \
  -o "$run_root/vkmt-java-jit-i386.dll"

for spec in \
    "vkmt-java-jit-x86_64.dll:IMAGE_FILE_MACHINE_AMD64" \
    "vkmt-java-jit-i386.dll:IMAGE_FILE_MACHINE_I386"; do
  dll=${spec%%:*}
  expected=${spec#*:}
  machine="$("$TOOL/llvm-readobj" --file-headers "$run_root/$dll" |
    awk '/^[[:space:]]*Machine:/ {print $2; exit}')"
  test "$machine" = "$expected"
  "$TOOL/llvm-readobj" --coff-exports "$run_root/$dll" \
    >"$run_root/$dll.exports"
  grep -q 'Name: Java_VkmtWindowsJavaJitProbe_nativeExecutableMemory' \
    "$run_root/$dll.exports"
done

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
  echo "Windows Java J3 wineboot failed" >&2
  tail -n 160 "$run_root/wineboot.log" >&2
  exit 1
}
VKMT_XTAJIT64_SOURCE="$X64_PROVIDER" VKMT_XTAJIT64_SHA256="$X64_PROVIDER_SHA" \
  VKMT_XTAJIT_SOURCE="$I386_PROVIDER" VKMT_XTAJIT_SHA256="$I386_PROVIDER_SHA" \
  "$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
VKMT_XTAJIT64_SOURCE="$X64_PROVIDER" VKMT_XTAJIT64_SHA256="$X64_PROVIDER_SHA" \
  VKMT_XTAJIT_SOURCE="$I386_PROVIDER" VKMT_XTAJIT_SHA256="$I386_PROVIDER_SHA" \
  "$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"

ditto "$JAVA_STAGE/x86_64" "$prefix/drive_c/vkmt/java-x86_64"
ditto "$JAVA_STAGE/i386" "$prefix/drive_c/vkmt/java-i386"
ditto "$classes" "$probe_dir/classes"
install -m 0644 "$run_root/vkmt-windows-java-j3.jar" \
  "$probe_dir/vkmt-windows-java-j3.jar"
install -m 0644 "$run_root/vkmt-java-jit-x86_64.dll" \
  "$probe_dir/vkmt-java-jit-x86_64.dll"
install -m 0644 "$run_root/vkmt-java-jit-i386.dll" \
  "$probe_dir/vkmt-java-jit-i386.dll"

x64_java="$prefix/drive_c/vkmt/java-x86_64/bin/java.exe"
i386_java="$prefix/drive_c/vkmt/java-i386/bin/java.exe"
classes_win='C:\vkmt\probe\classes'
jar_win='C:\vkmt\probe\vkmt-windows-java-j3.jar'
telemetry=(-XX:+UnlockDiagnosticVMOptions -XX:+PrintCompilation
  -XX:+PrintCodeCache -XX:+TraceClassUnloading)
compile_only=(-XX:CompileCommand=compileonly,VkmtWindowsJavaJitProbe.*
  -XX:CompileCommand=compileonly,vkmt/dynamic/JitPayload.*)
xcomp_scope=("${compile_only[@]}"
  -XX:CompileCommand=exclude,VkmtWindowsJavaJitProbe.main
  -XX:CompileCommand=exclude,VkmtWindowsJavaJitProbe.classLoaderWave
  -XX:CompileCommand=exclude,VkmtWindowsJavaJitProbe.exceptionResume)

run_lane()
{
  name=$1
  model=$2
  vm_kind=$3
  java_exe=$4
  jni_path=$5
  shift 5
  output="$run_root/$name.log"
  run_wine "$output" "$java_exe" "$@" \
    "-Dvkmt.jni=$jni_path" "-Dvkmt.probe.jar=$jar_win" \
    -cp "$classes_win" VkmtWindowsJavaJitProbe \
    "$model" "$vm_kind" "$name" || {
      echo "Windows Java J3 lane failed: $name" >&2
      tail -n 240 "$output" >&2
      exit 1
    }
  grep -Fq "VKMT_WINDOWS_JAVA_J3_OK model=$model" "$output"
  grep -Fq 'VKMT_J3_EXECMEM_OK transitions=257 flushes=257 patches=128' \
    "$output"
  grep -Fq 'VKMT_J3_HOT_OK' "$output"
  grep -Fq 'VKMT_J3_DEOPT_OK' "$output"
  test "$(grep -Fc 'VKMT_J3_CODECACHE_WAVE_OK' "$output")" -eq 4
  grep -Fq 'exceptions=VKMT_J3_EXCEPTIONS_OK' "$output"
  grep -Eq 'CodeCache:.*used=|CodeHeap .* used ' "$output"
  compiled="$(grep -Ec \
    '(VkmtWindowsJavaJitProbe|vkmt.dynamic.JitPayload)::' "$output" || true)"
  test "$compiled" -gt 0 || {
    echo "No fixture compilation records in $name" >&2
    exit 1
  }
  printf '%s=%s\n' "$name" "$compiled" >>"$run_root/compiled-counts.txt"
}

# x86_64 control lane first: normal Server tiering, then forced compilation.
run_lane x86_64-tiered 64 Server "$x64_java" \
  'C:\vkmt\probe\vkmt-java-jit-x86_64.dll' \
  -server -XX:CompileThreshold=100 "${telemetry[@]}" "${compile_only[@]}"
run_lane x86_64-xcomp 64 Server "$x64_java" \
  'C:\vkmt\probe\vkmt-java-jit-x86_64.dll' \
  -server -Xcomp "${telemetry[@]}" "${xcomp_scope[@]}"

# i386/WoW64 lane: low-threshold Client/C1, then forced compilation.
run_lane i386-c1 32 Client "$i386_java" \
  'C:\vkmt\probe\vkmt-java-jit-i386.dll' \
  -client -XX:-TieredCompilation -XX:CompileThreshold=100 \
  "${telemetry[@]}" "${compile_only[@]}"
run_lane i386-xcomp 32 Client "$i386_java" \
  'C:\vkmt\probe\vkmt-java-jit-i386.dll' \
  -client -Xcomp -XX:-TieredCompilation "${telemetry[@]}" \
  "${xcomp_scope[@]}"

WINEPREFIX="$prefix" "$WINESERVER" -k
WINEPREFIX="$prefix" "$WINESERVER" -w
for process_name in wine wineserver wine64-preloader wine-preloader java.exe; do
  ! pgrep -x "$process_name" >/dev/null 2>&1
done

mkdir -p "$EVIDENCE"
{
  printf 'candidate_i386_sha256=%s\n' "$I386_PROVIDER_SHA"
  printf 'candidate_x86_64_sha256=%s\n' "$X64_PROVIDER_SHA"
  printf 'golden_i386_sha256=%s\n' "$I386_GOLDEN_SHA"
  printf 'golden_x86_64_sha256=%s\n' "$X64_GOLDEN_SHA"
  printf 'jni_x86_64_sha256=%s\n' \
    "$(shasum -a 256 "$run_root/vkmt-java-jit-x86_64.dll" | awk '{print $1}')"
  printf 'jni_i386_sha256=%s\n' \
    "$(shasum -a 256 "$run_root/vkmt-java-jit-i386.dll" | awk '{print $1}')"
  cat "$run_root/compiled-counts.txt"
  for name in x86_64-tiered x86_64-xcomp i386-c1 i386-xcomp; do
    grep -F 'VKMT_WINDOWS_JAVA_J3_OK' "$run_root/$name.log"
  done
  printf 'exact_shutdown=1\n'
} >"$EVIDENCE/RESULTS.txt"
for name in x86_64-tiered x86_64-xcomp i386-c1 i386-xcomp; do
  grep -E '(^[[:space:]]*[0-9]+.*(VkmtWindowsJavaJitProbe|vkmt.dynamic.JitPayload)::)|CodeCache:|CodeHeap |VKMT_J3_' \
    "$run_root/$name.log" >"$EVIDENCE/$name-telemetry.txt"
done
install -m 0644 "$run_root/vkmt-java-jit-x86_64.dll.exports" \
  "$EVIDENCE/jni-x86_64-exports.txt"
install -m 0644 "$run_root/vkmt-java-jit-i386.dll.exports" \
  "$EVIDENCE/jni-i386-exports.txt"

printf '%s  %s\n' "$I386_GOLDEN_SHA" "$I386_GOLDEN" | shasum -a 256 -c -
printf '%s  %s\n' "$X64_GOLDEN_SHA" "$X64_GOLDEN" | shasum -a 256 -c -
printf '%s  %s\n' "$I386_GOLDEN_SHA" \
  "$BUILD/dlls/xtajit/aarch64-windows/xtajit.dll" | shasum -a 256 -c -
printf '%s  %s\n' "$X64_GOLDEN_SHA" \
  "$BUILD/dlls/xtajit64/aarch64-windows/xtajit64.dll" | shasum -a 256 -c -

echo "VKMT_WINDOWS_JAVA_J3_JIT_OK"
