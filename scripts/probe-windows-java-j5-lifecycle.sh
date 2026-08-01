#!/bin/bash
# Prove i386 HotSpot safepoints, thread context, JNI, APC, and VM lifecycle.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="${WINEBUILDDIR:-$VKMT/wine/build-ec}"
TOOL="$VKMT/toolchains/llvm-mingw-20260616-ucrt-macos-universal/bin"
RUNS="$VKMT/build/probe-runs"
WINE="$BUILD/wine"
WINESERVER="$BUILD/server/wineserver"
WINEBOOT="$BUILD/programs/wineboot/aarch64-windows/wineboot.exe"
JAVA_STAGE="$BUILD/java-runtime/i386"
NATIVE_JAVA="$VKMT/third_party/private/oracle-jre-8u501-arm64/Home/bin/java"
J5_SOURCE="$VKMT/test/java/VkmtWindowsJavaLifecycleProbe.java"
J5_JNI_SOURCE="$VKMT/test/java/windows_java_lifecycle.c"
GOLDEN_PROVIDER="$VKMT/wine/wine-11.12/runtime-providers/xtajit-arm64-known-good.dll"
GOLDEN_PROVIDER_SHA="$(shasum -a 256 "$GOLDEN_PROVIDER" | awk '{print $1}')"
PROVIDER="${VKMT_J5_XTAJIT_SOURCE:-$VKMT/build/fex-wow64-java-j5-divide/provider/xtajit.dll}"
PROVIDER_SHA="${VKMT_J5_XTAJIT_SHA256:-fe1345724f6a2950541966515f766099b7bce38701c9960d4be513c27ec81073}"
EVIDENCE="$VKMT/docs/validation/windows-java-j5-20260729"
LAUNCHES="${VKMT_J5_LAUNCHES:-10}"
CYCLES="${VKMT_J5_CYCLES:-10}"
MODE="${VKMT_J5_MODE:-lifecycle}"

for required in "$WINE" "$WINESERVER" "$WINEBOOT" "$NATIVE_JAVA" \
    "$J5_SOURCE" "$J5_JNI_SOURCE" "$PROVIDER" "$GOLDEN_PROVIDER"; do
  test -e "$required" || {
    echo "Missing Windows Java J5 input: $required" >&2
    exit 1
  }
done
test "$LAUNCHES" -gt 0
test "$CYCLES" -gt 0
test "$MODE" = lifecycle || test "$MODE" = exception-only ||
  test "$MODE" = gc-exception || test "$MODE" = gc-null ||
  test "$MODE" = gc-divide
printf '%s  %s\n' "$PROVIDER_SHA" "$PROVIDER" | shasum -a 256 -c -
printf '%s  %s\n' "$GOLDEN_PROVIDER_SHA" "$GOLDEN_PROVIDER" |
  shasum -a 256 -c -

"$VKMT/scripts/stage-windows-java-runtime.sh"
JNI_INCLUDE="$("$VKMT/scripts/fetch-java-jni-headers.sh")"
ECJ="$("$VKMT/scripts/fetch-java-test-tools.sh")"
test -f "$JNI_INCLUDE/jni.h"
test -f "$JNI_INCLUDE/win32/jni_md.h"
test -f "$ECJ"

mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/windows-java.j5.XXXXXX")"
prefix="$run_root/prefix"
wine_pid=
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=10s \
    "${VKMT_JAVA_J5_TIMEOUT:-900}s")
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=10s \
    "${VKMT_JAVA_J5_TIMEOUT:-900}s")
fi

j5_guest_pids()
{
  ps -axo pid=,command= | awk '
    index($0, "C:\\vkmt\\java-i386\\bin\\java.exe") &&
    index($0, "VkmtWindowsJavaLifecycleProbe") { print $1 }
  '
}

cleanup()
{
  status=$?
  test -z "$wine_pid" || kill -TERM "$wine_pid" 2>/dev/null || true
  for pid in $(j5_guest_pids); do kill -TERM "$pid" 2>/dev/null || true; done
  WINEPREFIX="$prefix" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$prefix" "$WINESERVER" -w 2>/dev/null || true
  for pid in $(j5_guest_pids); do kill -KILL "$pid" 2>/dev/null || true; done
  case "$run_root" in
    "$RUNS"/*)
      if test "${VKMT_KEEP_JAVA_J5_RUN:-0}" = 1; then
        echo "Retained Windows Java J5 run: $run_root" >&2
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
    WINEBOOTSTRAPMODE=1 WINE_NO_EXPLORER=1 \
    WINEDEBUG="${VKMT_JAVA_J5_WINEDEBUG:--all}" \
    FEX_TSOENABLED=0 FEX_VECTORTSOENABLED=0 FEX_MEMCPYSETTSOENABLED=0 \
    FEX_SILENTLOG="${VKMT_JAVA_J5_FEX_SILENTLOG:-1}" \
    MVK_CONFIG_LOG_LEVEL=0 \
    "$WINE" "$@" >"$output" 2>&1 &
  wine_pid=$!
  if wait "$wine_pid"; then result=0; else result=$?; fi
  wine_pid=
  return "$result"
}

classes="$run_root/classes"
mkdir -p "$classes"
"$NATIVE_JAVA" -server -jar "$ECJ" -1.8 -proc:none -d "$classes" \
  "$J5_SOURCE"
test -f "$classes/VkmtWindowsJavaLifecycleProbe.class"

"$TOOL/i686-w64-mingw32-clang" -O2 -Wall -Wextra \
  -Wno-ignored-attributes -shared -Wl,--kill-at \
  -I"$JNI_INCLUDE" -I"$JNI_INCLUDE/win32" "$J5_JNI_SOURCE" \
  -o "$run_root/vkmt-java-lifecycle-i386.dll"

for dll in vkmt-java-lifecycle-i386.dll; do
  machine="$("$TOOL/llvm-readobj" --file-headers "$run_root/$dll" |
    awk '/^[[:space:]]*Machine:/ {print $2; exit}')"
  test "$machine" = IMAGE_FILE_MACHINE_I386
  "$TOOL/llvm-readobj" --coff-exports "$run_root/$dll" \
    >"$run_root/$dll.exports"
done
grep -q \
  'Name: Java_VkmtWindowsJavaLifecycleProbe_nativeSuspendContextResume' \
  "$run_root/vkmt-java-lifecycle-i386.dll.exports"
grep -q 'Name: Java_VkmtWindowsJavaLifecycleProbe_nativeAttachCallback' \
  "$run_root/vkmt-java-lifecycle-i386.dll.exports"
grep -q 'Name: Java_VkmtWindowsJavaLifecycleProbe_nativeApcRoundtrip' \
  "$run_root/vkmt-java-lifecycle-i386.dll.exports"

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
done < <(find "$BUILD/dlls" -type f \
  -path '*/i386-windows/*.dll' -print | LC_ALL=C sort)

"$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
run_wine "$run_root/wineboot.log" "$WINEBOOT" --init || {
  echo "Windows Java J5 wineboot failed" >&2
  tail -n 180 "$run_root/wineboot.log" >&2
  exit 1
}
VKMT_XTAJIT_SOURCE="$PROVIDER" VKMT_XTAJIT_SHA256="$PROVIDER_SHA" \
  "$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
VKMT_XTAJIT_SOURCE="$PROVIDER" VKMT_XTAJIT_SHA256="$PROVIDER_SHA" \
  "$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"

ditto "$JAVA_STAGE" "$prefix/drive_c/vkmt/java-i386"
ditto "$classes" "$probe_dir/classes"
install -m 0644 "$run_root/vkmt-java-lifecycle-i386.dll" \
  "$probe_dir/vkmt-java-lifecycle-i386.dll"

java_exe="$prefix/drive_c/vkmt/java-i386/bin/java.exe"
classes_win='C:\vkmt\probe\classes'

telemetry=(-XX:+UnlockDiagnosticVMOptions -XX:+PrintCompilation
  -XX:CompileCommand=compileonly,VkmtWindowsJavaLifecycleProbe.hotKernel
  -XX:CompileCommand=compileonly,VkmtWindowsJavaLifecycleProbe.compiledExceptionContract)
diagnostic_options=()
test "${VKMT_J5_SKIP_CONTEXT:-0}" != 1 ||
  diagnostic_options+=(-Dvkmt.j5.skipContext=true)
test "${VKMT_J5_SKIP_GC:-0}" != 1 ||
  diagnostic_options+=(-Dvkmt.j5.skipGC=true)
test "${VKMT_J5_SKIP_APC:-0}" != 1 ||
  diagnostic_options+=(-Dvkmt.j5.skipAPC=true)

: >"$run_root/lifecycle-results.txt"
for launch in $(jot "$LAUNCHES" 0); do
  log="$run_root/lifecycle-$launch.log"
  mode_arg=()
  test "$MODE" = lifecycle || mode_arg=("$MODE")
  run_wine "$log" "$java_exe" -client -XX:-TieredCompilation \
    -XX:CompileThreshold=50 -XX:ErrorFile='C:\vkmt\probe\hs_err_pid%p.log' \
    -Xms32m -Xmx64m "${telemetry[@]}" \
    ${diagnostic_options[@]+"${diagnostic_options[@]}"} \
    '-Dvkmt.jni=C:\vkmt\probe\vkmt-java-lifecycle-i386.dll' \
    -cp "$classes_win" VkmtWindowsJavaLifecycleProbe \
    "$launch" "$CYCLES" ${mode_arg[@]+"${mode_arg[@]}"} || {
      echo "Windows Java J5 lifecycle launch failed: $launch" >&2
      tail -n 320 "$log" >&2
      mkdir -p "$EVIDENCE"
      for crash_log in "$probe_dir"/hs_err_pid*.log; do
        test -f "$crash_log" || continue
        install -m 0644 "$crash_log" \
          "$EVIDENCE/$(basename "$crash_log" .log)-launch-$launch.log"
      done
      exit 1
    }
  if test "$MODE" = exception-only; then
    grep -Fq 'VKMT_J5_EXCEPTION_ONLY_OK' "$log"
    continue
  fi
  if test "$MODE" = gc-exception || test "$MODE" = gc-null ||
      test "$MODE" = gc-divide; then
    grep -Fq 'VKMT_J5_GC_EXCEPTION_OK' "$log"
    continue
  fi
  test "$(grep -Fc "VKMT_J5_CYCLE_OK launch=$launch" "$log")" \
    -eq "$CYCLES"
  grep -Fq "VKMT_WINDOWS_JAVA_J5_OK launch=$launch cycles=$CYCLES" \
    "$log"
  grep -Eq 'VkmtWindowsJavaLifecycleProbe::hotKernel' "$log"
  grep -F "VKMT_WINDOWS_JAVA_J5_OK launch=$launch" "$log" \
    >>"$run_root/lifecycle-results.txt"
  if j5_guest_pids >"$run_root/retained-java.txt" &&
      test -s "$run_root/retained-java.txt"; then
    echo "Windows Java J5 retained a JVM after launch $launch" >&2
    cat "$run_root/retained-java.txt" >&2
    exit 1
  fi
done

if test "$MODE" = exception-only || test "$MODE" = gc-exception ||
    test "$MODE" = gc-null || test "$MODE" = gc-divide; then
  WINEPREFIX="$prefix" "$WINESERVER" -k
  WINEPREFIX="$prefix" "$WINESERVER" -w
  echo "VKMT_WINDOWS_JAVA_J5_EXCEPTION_ONLY_OK"
  exit 0
fi

expected_cycles=$((LAUNCHES * CYCLES))
actual_cycles="$(grep -hFc 'VKMT_J5_CYCLE_OK' \
  "$run_root"/lifecycle-*.log | awk '{sum += $1} END {print sum + 0}')"
test "$actual_cycles" -eq "$expected_cycles"

WINEPREFIX="$prefix" "$WINESERVER" -k
WINEPREFIX="$prefix" "$WINESERVER" -w
if j5_guest_pids >"$run_root/retained-java-final.txt" &&
    test -s "$run_root/retained-java-final.txt"; then
  echo "Windows Java J5 retained a final JVM process" >&2
  cat "$run_root/retained-java-final.txt" >&2
  exit 1
fi

if test -d "$EVIDENCE"; then
  find "$EVIDENCE" -depth -delete
fi
mkdir -p "$EVIDENCE"
{
  printf 'provider_sha256=%s\n' "$PROVIDER_SHA"
  printf 'wow64_sha256=%s\n' \
    "$(shasum -a 256 "$BUILD/dlls/wow64/aarch64-windows/wow64.dll" |
      awk '{print $1}')"
  printf 'jni_sha256=%s\n' \
    "$(shasum -a 256 "$run_root/vkmt-java-lifecycle-i386.dll" |
      awk '{print $1}')"
  printf 'launches=%s\n' "$LAUNCHES"
  printf 'cycles_per_launch=%s\n' "$CYCLES"
  printf 'total_cycles=%s\n' "$actual_cycles"
  cat "$run_root/lifecycle-results.txt"
  printf 'exact_shutdown=1\n'
} >"$EVIDENCE/RESULTS.txt"
install -m 0644 "$run_root/vkmt-java-lifecycle-i386.dll.exports" \
  "$EVIDENCE/jni-i386-exports.txt"
grep -hE 'VkmtWindowsJavaLifecycleProbe::(hotKernel|compiledExceptionContract)|VKMT_J5_(CYCLE_OK|CONTEXT|PHASE)' \
  "$run_root"/lifecycle-*.log >"$EVIDENCE/compilation-and-cycles.txt"

printf '%s  %s\n' "$PROVIDER_SHA" "$PROVIDER" | shasum -a 256 -c -
printf '%s  %s\n' "$GOLDEN_PROVIDER_SHA" "$GOLDEN_PROVIDER" |
  shasum -a 256 -c -
echo "VKMT_WINDOWS_JAVA_J5_LIFECYCLE_OK"
