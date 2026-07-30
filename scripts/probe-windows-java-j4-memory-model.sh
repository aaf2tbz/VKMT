#!/bin/bash
# Prove i386 HotSpot/FEX x86 memory-model semantics on ARM64 Darwin.
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
JAVA_SOURCE="$VKMT/test/java/VkmtWindowsJavaMemoryModelProbe.java"
JNI_SOURCE="$VKMT/test/java/windows_java_memory_primitives.c"
GOLDEN="$VKMT/wine/wine-11.12/runtime-providers/xtajit-arm64-known-good.dll"
GOLDEN_SHA=fe1345724f6a2950541966515f766099b7bce38701c9960d4be513c27ec81073
CANDIDATE="${VKMT_XTAJIT_SOURCE:-$VKMT/build/fex-wow64-java-final/provider/xtajit.dll}"
CANDIDATE_SHA="${VKMT_XTAJIT_SHA256:-}"
EVIDENCE="$VKMT/docs/validation/windows-java-j4-20260729"

for required in "$WINE" "$WINESERVER" "$WINEBOOT" "$NATIVE_JAVA" \
    "$JAVA_SOURCE" "$JNI_SOURCE" "$GOLDEN" "$CANDIDATE"; do
  test -e "$required" || {
    echo "Missing Windows Java J4 input: $required" >&2
    exit 1
  }
done
if test -z "$CANDIDATE_SHA"; then
  CANDIDATE_SHA="$(shasum -a 256 "$CANDIDATE" | awk '{print $1}')"
fi
printf '%s  %s\n' "$GOLDEN_SHA" "$GOLDEN" | shasum -a 256 -c -
printf '%s  %s\n' "$CANDIDATE_SHA" "$CANDIDATE" | shasum -a 256 -c -

"$VKMT/scripts/stage-windows-java-runtime.sh"
JNI_INCLUDE="$("$VKMT/scripts/fetch-java-jni-headers.sh")"
ECJ="$("$VKMT/scripts/fetch-java-test-tools.sh")"
test -f "$JNI_INCLUDE/jni.h"
test -f "$JNI_INCLUDE/win32/jni_md.h"
test -f "$ECJ"

mkdir -p "$RUNS"
run_root="$(mktemp -d "$RUNS/windows-java.j4.XXXXXX")"
prefix=
wine_pid=
timeout_cmd=()
if command -v gtimeout >/dev/null 2>&1; then
  timeout_cmd=(gtimeout --signal=TERM --kill-after=10s \
    "${VKMT_JAVA_J4_TIMEOUT:-180}s")
elif command -v timeout >/dev/null 2>&1; then
  timeout_cmd=(timeout --signal=TERM --kill-after=10s \
    "${VKMT_JAVA_J4_TIMEOUT:-180}s")
fi

stop_prefix()
{
  target=$1
  test -d "$target" || return 0
  WINEPREFIX="$target" "$WINESERVER" -k 2>/dev/null || true
  WINEPREFIX="$target" "$WINESERVER" -w 2>/dev/null || true
}

remove_prefix()
{
  target=$1
  stop_prefix "$target"
  case "$target" in
    "$run_root"/prefix-*)
      /bin/rm -rf -- "$target"
      ;;
    *)
      echo "Refusing to remove unexpected J4 prefix: $target" >&2
      return 1
      ;;
  esac
}

cleanup()
{
  status=$?
  test -z "$wine_pid" || kill -TERM "$wine_pid" 2>/dev/null || true
  test -z "$prefix" || stop_prefix "$prefix"
  case "$run_root" in
    "$RUNS"/*)
      if test "${VKMT_KEEP_JAVA_J4_RUN:-0}" = 1; then
        echo "Retained Windows Java J4 run: $run_root" >&2
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
mkdir -p "$classes"
"$NATIVE_JAVA" -server -jar "$ECJ" -1.8 -proc:none -d "$classes" \
  "$JAVA_SOURCE"
test -f "$classes/VkmtWindowsJavaMemoryModelProbe.class"

"$TOOL/i686-w64-mingw32-clang" -O2 -mmmx -Wall -Wextra \
  -Wno-ignored-attributes -shared -Wl,--kill-at \
  -I"$JNI_INCLUDE" -I"$JNI_INCLUDE/win32" "$JNI_SOURCE" \
  -o "$run_root/vkmt-java-memory-i386.dll"
machine="$("$TOOL/llvm-readobj" --file-headers \
  "$run_root/vkmt-java-memory-i386.dll" |
  awk '/^[[:space:]]*Machine:/ {print $2; exit}')"
test "$machine" = IMAGE_FILE_MACHINE_I386
"$TOOL/llvm-readobj" --coff-exports \
  "$run_root/vkmt-java-memory-i386.dll" \
  >"$run_root/vkmt-java-memory-i386.dll.exports"
grep -q \
  'Name: Java_VkmtWindowsJavaMemoryModelProbe_nativeMemoryPrimitives' \
  "$run_root/vkmt-java-memory-i386.dll.exports"

# This is a mandatory pre-JVM gate: generated ARM64 must already demonstrate
# conservative software-TSO lowering, including the deliberately unaligned
# and locked-operation paths, and must contain no LDAPR shortcut.
VKMT_XTAJIT_SOURCE="$CANDIDATE" VKMT_XTAJIT_SHA256="$CANDIDATE_SHA" \
  "$VKMT/scripts/probe-windows-java-j0-tso.sh" \
  >"$run_root/j0-tso.log" 2>&1 || {
    echo "Windows Java J4 candidate failed the pre-JVM TSO gate" >&2
    tail -n 200 "$run_root/j0-tso.log" >&2
    exit 1
  }
grep -Fq 'VKMT_WINDOWS_JAVA_J0_TSO_OK' "$run_root/j0-tso.log"

prepare_prefix()
{
  provider=$1
  provider_sha=$2
  prefix=$3
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
  run_wine "$run_root/$(basename "$prefix")-wineboot.log" \
    "$WINEBOOT" --init
  VKMT_XTAJIT_SOURCE="$provider" VKMT_XTAJIT_SHA256="$provider_sha" \
    "$VKMT/scripts/stage-runtime-providers.sh" --prefix "$prefix"
  VKMT_XTAJIT_SOURCE="$provider" VKMT_XTAJIT_SHA256="$provider_sha" \
    "$VKMT/scripts/stage-runtime-providers.sh" --verify-prefix "$prefix"

  ditto "$JAVA_STAGE" "$prefix/drive_c/vkmt/java-i386"
  ditto "$classes" "$probe_dir/classes"
  install -m 0644 "$run_root/vkmt-java-memory-i386.dll" \
    "$probe_dir/vkmt-java-memory-i386.dll"
}

run_provider()
{
  name=$1
  provider=$2
  provider_sha=$3
  combined="$run_root/$name.log"
  : >"$combined"
  provider_gc_events=0
  for provider_run in 1 2 3; do
    prefix="$run_root/prefix-$name-$provider_run"
    prepare_prefix "$provider" "$provider_sha" "$prefix" || {
      result=$?
      remove_prefix "$prefix"
      prefix=
      return "$result"
    }
    java_exe="$prefix/drive_c/vkmt/java-i386/bin/java.exe"
    memory_log="$run_root/$name-run$provider_run-memory.log"
    if run_wine "$memory_log" "$java_exe" -client \
      -XX:-TieredCompilation -XX:CompileThreshold=100 -Xms32m -Xmx64m \
      '-Dvkmt.jni=C:\vkmt\probe\vkmt-java-memory-i386.dll' \
      -cp 'C:\vkmt\probe\classes' VkmtWindowsJavaMemoryModelProbe \
      "$name" memory 1; then
      :
    else
      result=$?
      cat "$memory_log" >>"$combined"
      remove_prefix "$prefix"
      prefix=
      return "$result"
    fi
    if ! grep -Fq \
        "VKMT_J4_ROUND_OK provider=$name mode=memory round=0" \
        "$memory_log" ||
        ! grep -Fq \
          "VKMT_WINDOWS_JAVA_J4_OK provider=$name mode=memory rounds=1" \
          "$memory_log"; then
      cat "$memory_log" >>"$combined"
      remove_prefix "$prefix"
      prefix=
      return 1
    fi

    gc_log="$run_root/$name-run$provider_run-gc.log"
    if run_wine "$gc_log" "$java_exe" -client -Xint \
      -Xms32m -Xmx64m -verbose:gc \
      '-Dvkmt.jni=C:\vkmt\probe\vkmt-java-memory-i386.dll' \
      -cp 'C:\vkmt\probe\classes' VkmtWindowsJavaMemoryModelProbe \
      "$name" gc 1; then
      :
    else
      result=$?
      cat "$memory_log" "$gc_log" >>"$combined"
      remove_prefix "$prefix"
      prefix=
      return "$result"
    fi
    if ! grep -Fq "VKMT_J4_ROUND_OK provider=$name mode=gc round=0" \
        "$gc_log" ||
        ! grep -Fq \
          "VKMT_WINDOWS_JAVA_J4_OK provider=$name mode=gc rounds=1" \
          "$gc_log"; then
      cat "$memory_log" "$gc_log" >>"$combined"
      remove_prefix "$prefix"
      prefix=
      return 1
    fi
    gc_events="$(grep -Ec '\[GC|GC \(' "$gc_log" || true)"
    test "$gc_events" -gt 0 || {
      echo "J4 did not observe an allocation-driven GC: $name run " \
        "$provider_run" >&2
      cat "$memory_log" "$gc_log" >>"$combined"
      remove_prefix "$prefix"
      prefix=
      return 1
    }
    provider_gc_events=$((provider_gc_events + gc_events))
    printf 'VKMT_J4_PROVIDER_RUN=%s\n' "$provider_run" >>"$combined"
    cat "$memory_log" "$gc_log" >>"$combined"
    remove_prefix "$prefix"
    prefix=
  done
  test "$(grep -Fc "VKMT_J4_ROUND_OK provider=$name" "$combined")" -eq 6
  printf '%s_gc_events=%s\n' "$name" "$provider_gc_events" \
    >>"$run_root/gc-counts.txt"
}

# Establish behavior with the accepted provider first. A golden failure does
# not contaminate the candidate attempt: its wineserver is stopped and its
# complete prefix is deleted before the next prefix is created.
golden_status=fail
candidate_status=not-needed
selected_provider=
if run_provider golden "$GOLDEN" "$GOLDEN_SHA"; then
  golden_status=pass
  selected_provider=golden
else
  golden_rc=$?
  printf 'golden_rc=%s\n' "$golden_rc" >"$run_root/golden-status.txt"
fi
if test "$golden_status" = fail; then
  if run_provider candidate "$CANDIDATE" "$CANDIDATE_SHA"; then
    candidate_status=pass
    selected_provider=candidate
  else
    candidate_rc=$?
    candidate_status=fail
    echo \
      "Windows Java J4 candidate memory-model gate failed (rc=$candidate_rc)" \
      >&2
    tail -n 260 "$run_root/candidate.log" >&2
    exit "$candidate_rc"
  fi
fi

mkdir -p "$EVIDENCE"
{
  printf 'golden_status=%s\n' "$golden_status"
  printf 'candidate_status=%s\n' "$candidate_status"
  printf 'selected_provider=%s\n' "$selected_provider"
  test ! -f "$run_root/golden-status.txt" ||
    cat "$run_root/golden-status.txt"
  printf 'golden_sha256=%s\n' "$GOLDEN_SHA"
  printf 'candidate_sha256=%s\n' "$CANDIDATE_SHA"
  printf 'jni_i386_sha256=%s\n' \
    "$(shasum -a 256 "$run_root/vkmt-java-memory-i386.dll" |
      awk '{print $1}')"
  printf 'jni_machine=%s\n' "$machine"
  grep -F 'VKMT_J4_ROUND_OK' "$run_root/$selected_provider.log"
  grep -F 'VKMT_WINDOWS_JAVA_J4_OK' "$run_root/$selected_provider.log"
  cat "$run_root/gc-counts.txt"
  printf 'software_tso=1\n'
  printf 'hardware_tso=0\n'
  printf 'exact_shutdown=1\n'
} >"$EVIDENCE/RESULTS.txt"
install -m 0644 "$run_root/vkmt-java-memory-i386.dll.exports" \
  "$EVIDENCE/jni-i386-exports.txt"
install -m 0644 "$run_root/j0-tso.log" "$EVIDENCE/j0-tso.log"
if test "$golden_status" = fail; then
  install -m 0644 "$run_root/golden.log" "$EVIDENCE/golden-failure.log"
fi

# Neither the side candidate nor either disposable prefix may alter the
# accepted provider in the source or canonical build tree.
"$VKMT/scripts/stage-runtime-providers.sh"
printf '%s  %s\n' "$GOLDEN_SHA" "$GOLDEN" | shasum -a 256 -c -
printf '%s  %s\n' "$GOLDEN_SHA" \
  "$BUILD/dlls/xtajit/aarch64-windows/xtajit.dll" | shasum -a 256 -c -

prefix=
echo "VKMT_WINDOWS_JAVA_J4_MEMORY_MODEL_OK"
