# Windows Java phase J6 acceptance

J6 completed on 2026-07-29. The final accepted runtime uses the promoted J5
i386/WoW64 provider and the established x86_64 provider:

- i386 `xtajit.dll`:
  `fe1345724f6a2950541966515f766099b7bce38701c9960d4be513c27ec81073`;
- x86_64 `xtajit64.dll`:
  `7b9f55ceabe971ffa1f514570bb54ed7b5640959e4440e7f8a013e9af13ab7e6`;
- ARM64 `wow64.dll`:
  `3f252921f12806907c78a4bf07c1aa5a761ba7882d3b72bb876c1dc316f93e7b`.

## Unified-prefix gate

`scripts/probe-windows-java-j6-unified.sh` created one fresh prefix and ran,
sequentially:

1. Oracle JRE 8u501 native ARM64 Server VM through the Wine-to-native handoff,
   including ARM64 JNI and local TLS;
2. Temurin 8u492 Windows x86_64 Server VM with normal JIT execution;
3. Temurin 8u472 Windows i386 Client VM with normal C1 execution;
4. ARM64, ARM64EC, x86_64, and i386 Wine architecture fixtures.

All lanes passed. The exact wineserver stopped and waited, no Java/Wine
process remained, and the exact disposable root was deleted. Machine-readable
markers are in `RESULTS.txt`.

## Post-promotion regressions

The final canonical build then passed, without provider override variables:

- the complete Phase 4 WoW64 contract: load, syscall return, TLS, context,
  SEH, APC, second thread, callback return, and repeated thread lifecycle;
- i386 VKMT DLL loading, DXGI adapter enumeration, D3D12
  queue/fence/copy/readback, and D3D11 clear/copy/readback;
- Gecko/MSHTML on x86_64 and i386, including i386 HTTPS;
- OpenGL runtime and GLSL 1.20, 3.30, and 4.50 Metal draw/readback on ARM64,
  ARM64EC, x86_64, and i386;
- SDL2 and SDL3 on ARM64, ARM64EC, x86_64, and i386;
- the ordinary ARM64/ARM64EC/x86_64/i386 single-prefix baseline.

The corresponding terminal logs are retained beside this file.

## x86_64 candidate disposition

The side J3 x86_64 candidate was not promoted. Prefix-only testing had not
selected it because build-tree Wine resolves `xtajit64` from
`wine/build-ec/dlls/xtajit64`. Placing the experimental binary in that actual
load path reproducibly faulted in its tier-0 interpreter while launching the
x86_64 JVM. The established provider was restored byte-for-byte and passed
the complete final suite. The rejected side candidate remains available for
future isolated development and is not part of the accepted runtime.

## Recovery image

The full source-integrated passing state was archived to
`/Volumes/AverySSD/VKMT_snapshots/VKMT-runtime-j6-20260729-1738.tar.zst`.
It is 4.38 GiB with SHA-256
`be5f656e857f3fb1d3b8a9ec528655e22947372dfa1651244b1d2bc9d49a2298`.
The archive passed `zstd -t`; its adjacent manifest contains 322,137 entries
and includes the accepted Wine runtime, canonical providers, Java runtimes,
source trees, J5 patches, and J6 validation tooling.
