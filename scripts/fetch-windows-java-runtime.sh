#!/bin/bash
# Fetch the two checksum-pinned Windows Java 8 guest runtimes.
set -euo pipefail

VKMT="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$VKMT/third_party/windows-java"

I386_NAME=OpenJDK8U-jre_x86-32_windows_hotspot_8u472b08.zip
I386_URL=https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u472-b08/OpenJDK8U-jre_x86-32_windows_hotspot_8u472b08.zip
I386_SHA=21a2c5af684a658f1484daa85eabf4961ab9de28c0efbf31da2381d77fce3b5f
X64_NAME=OpenJDK8U-jre_x64_windows_hotspot_8u492b09.zip
X64_URL=https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u492-b09/OpenJDK8U-jre_x64_windows_hotspot_8u492b09.zip
X64_SHA=bb25b002556afc7ef158cd95ec6270dddb3eecba69acdd7abb9d28b2e9ff0f5e

fetch()
{
  url=$1
  output=$2
  expected=$3

  if test -f "$output"; then
    printf '%s  %s\n' "$expected" "$output" | shasum -a 256 -c -
    return
  fi
  test ! -e "$output" || {
    echo "Refusing to replace non-file Java input: $output" >&2
    exit 1
  }

  partial="$output.part"
  test ! -e "$partial" || {
    echo "Refusing to replace stale partial download: $partial" >&2
    exit 1
  }
  curl --fail --location --retry 3 --output "$partial" "$url"
  printf '%s  %s\n' "$expected" "$partial" | shasum -a 256 -c -
  mv "$partial" "$output"
}

mkdir -p "$ROOT"
fetch "$I386_URL" "$ROOT/$I386_NAME" "$I386_SHA"
fetch "$X64_URL" "$ROOT/$X64_NAME" "$X64_SHA"

echo "VKMT_WINDOWS_JAVA_INPUTS_OK"
