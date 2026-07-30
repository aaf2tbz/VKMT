# Windows Java J2 services and JNI acceptance

Phase J2 passed on 2026-07-29 with:

```sh
scripts/probe-windows-java-j2-services.sh
```

Terminal marker:

`VKMT_WINDOWS_JAVA_J2_SERVICES_OK`

## Single-prefix order and providers

One fresh prefix ran the x86_64 control lane first and the i386/WoW64 lane
second. Both JVMs ran in interpreted mode. The x86_64 lane used the accepted
ARM64EC provider `7b9f55ce...`; the i386 lane used the unpromoted J0
software-TSO candidate `f7ace198...`.

The accepted provider files remained byte-identical after the run.

## Architecture-matched JNI boundary

The probe built both Windows JNI DLLs from `test/java/windows_java_jni.c`
with the in-tree LLVM-MinGW toolchain and the pinned OpenJDK 8u472-b08 JNI
headers:

- x86_64: PE32+, SHA-256 `4fd41ee5e7a8fb6ecd4383118cb433684d8ad860b625dcbe78f74351b2371106`
- i386: PE32, SHA-256 `09f45bec481481e430af5b9029e569f161f06cf9b06de47e4c1ee63bc838d4dd`

Both export `JNI_OnLoad` and the required native entry points. Both JVMs
passed JNI load and lookup, callbacks, Java-exception observation and
clearing, and attach/callback/detach from a second Windows native thread.

The i386 lane reported `pointerBits=32` and native address `0x78925034`.
No host-width pointer appeared in a Java-visible value.

## Shared service gates

Both architectures produced the same semantic success markers for:

- allocation pressure, explicit GC, and direct buffers;
- mapped-file write, force, and readback;
- 32 isolated class-loader loads and reflective calls;
- threads, monitor wait/notify, and `ThreadLocal`;
- Java exceptions and `StackOverflowError`;
- same-architecture `ProcessBuilder` child execution and environment
  inheritance;
- loopback sockets and deterministic local HTTPS/TLS;
- native `QueryPerformanceCounter` plus `Sleep`, and Java
  `System.nanoTime` plus `Thread.sleep`;
- shutdown hooks.

The machine-readable records in `RESULTS.txt` contain the complete markers
and measured timing values.

## Cleanup and lifecycle

Both child JVMs returned normally. Each shutdown hook ran, each mapped file
was removed at VM shutdown, and the exact wineserver was stopped and waited.
No Wine, Java, TLS-server process, or J2 prefix remains. The J0 provider
candidate was not promoted.
