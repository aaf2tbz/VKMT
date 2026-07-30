# Windows Java J1 interpreter acceptance

Phase J1 passed on 2026-07-29 with:

```sh
scripts/probe-windows-java-j1-interpreters.sh
```

Terminal marker:

`VKMT_WINDOWS_JAVA_J1_INTERPRETERS_OK`

## Single-prefix order and providers

One fresh prefix ran the x86_64 control lane first and the i386/WoW64 lane
second. The x86_64 lane used the accepted ARM64EC provider
`7b9f55ce...`. The i386 lane used the unpromoted J0 software-TSO candidate:

`f7ace1980b33e270c9ee8b9d240705a82bcface99e868ff65895a3dbcfd4d247`

Before either JVM launched, the i386 TSO publication/CAS fixture passed:

`JAVA_TSO_PREFLIGHT_OK checksum=00000000a5a50ff0 aligned32=12345678 aligned64=1122334455667788`

## x86_64 control lane

Temurin 8u492-b09 reported:

- `OpenJDK 64-Bit Server VM`;
- `sun.arch.data.model=64`;
- `os.arch=amd64`;
- `-server -Xint` as `interpreted mode`.

Both launch forms passed:

- class path:
  `VKMT_WINDOWS_JAVA_J1_OK mode=classpath model=64`
- executable JAR:
  `VKMT_WINDOWS_JAVA_J1_OK mode=jar model=64`

## i386/WoW64 lane

Temurin 8u472-b08 reported:

- `OpenJDK Client VM`;
- `sun.arch.data.model=32`;
- `os.arch=x86`;
- `-client -Xint` as `interpreted mode`.

Both launch forms passed:

- class path:
  `VKMT_WINDOWS_JAVA_J1_OK mode=classpath model=32`
- executable JAR:
  `VKMT_WINDOWS_JAVA_J1_OK mode=jar model=32`

## Shared semantic fixture

Both architectures and both launch forms proved:

- reflection invocation;
- loading `vkmt.dynamic.DynamicPayload` through an isolated
  `URLClassLoader`;
- opening the executable JAR as a ZIP;
- reading and validating `vkmt/payload.txt`;
- normal VM return.

The common markers were:

- `dynamic=VKMT_J1_REFLECTION_OK`
- `zip=VKMT_J1_ZIP_OK`

## Preservation and cleanup

The exact wineserver was stopped and waited. No Java, Wine, or J1 prefix
remains. Both golden provider source/build copies retained their accepted
hashes. The J0 i386 candidate was staged only inside the disposable prefix
and was not promoted.

Machine-readable results and retained version logs are beside this file.
