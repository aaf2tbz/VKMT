#!/bin/bash
# Fetch the checksum-pinned OpenJDK 8 Windows JNI development headers.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$VKMT/third_party/java-jni-headers/openjdk8u472-b08/include"
JNI="$ROOT/jni.h"
JNI_MD="$ROOT/win32/jni_md.h"
JNI_SHA=ed99792df48670072b78028faf704a8dcb6868fe140ccc7eced9b01dfa62fef4
JNI_MD_SHA=5479fb385ea1e11619f5c0cdfd9ccb3ea3a3fea0f5bc6176fb3ce62be29d759b
BASE=https://raw.githubusercontent.com/openjdk/jdk8u/jdk8u472-b08

mkdir -p "$ROOT/win32"
if test ! -f "$JNI"; then
  curl -fL --retry 3 \
    "$BASE/jdk/src/share/javavm/export/jni.h" -o "$JNI"
fi
if test ! -f "$JNI_MD"; then
  curl -fL --retry 3 \
    "$BASE/jdk/src/windows/javavm/export/jni_md.h" -o "$JNI_MD"
fi

printf '%s  %s\n' "$JNI_SHA" "$JNI" | shasum -a 256 -c - >&2
printf '%s  %s\n' "$JNI_MD_SHA" "$JNI_MD" | shasum -a 256 -c - >&2
echo "$ROOT"
