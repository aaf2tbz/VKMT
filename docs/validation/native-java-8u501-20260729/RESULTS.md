# Native ARM64 Java 8u501 acceptance — 2026-07-29

`scripts/probe-native-java-runtime.sh` passed from a fresh disposable Wine
prefix and emitted:

```text
VKMT_NATIVE_ORACLE_JRE_8U501_STAGE_OK
VKMT_NATIVE_JAVA_HANDOFF_PREFIX_OK
VKMT_NATIVE_JAVA_8U501_SERVER_CLASS_JNI_TLS_OK
VKMT_NATIVE_JAVA_WINE_PREFIX_HANDOFF_OK
VKMT_NATIVE_JAVA_8U501_ALL_OK
```

Accepted surfaces:

- the private Oracle JRE 8u501 DMG matches its pinned SHA-256;
- `java` and `lib/server/libjvm.dylib` are signed ARM64 Mach-O binaries with
  no Homebrew dependency;
- `java -server` selects `Java HotSpot(TM) 64-Bit Server VM`;
- Java 8 class-path execution and executable-JAR launch pass;
- an ARM64 JNI dylib loads and returns the expected 64-bit token;
- a deterministic local TLS 1.2 connection completes, exposes a negotiated
  cipher suite, validates that the peer supplied a certificate, and returns
  the expected HTTPS response;
- a native ARM64 PE installed at
  `C:\vkmt\bin\vkmt-native-java-handoff.exe` starts that same host Server VM
  through Wine's `__wine_unix_spawnvp` boundary;
- the handoff PE is compiled with `-ffixed-x18 -ffixed-x28` and its
  disassembly contains no `x18` use;
- the exact wineserver receives `-k` and `-w`, and the probe root is removed.

Eclipse ECJ 4.6.1 is pinned only as a build-time fixture compiler. It is not
part of the shipped Oracle runtime. The JRE remains private and must not be
redistributed outside this runtime.
