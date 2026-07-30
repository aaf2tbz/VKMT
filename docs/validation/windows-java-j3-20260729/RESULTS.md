# Windows Java J3 HotSpot JIT acceptance

Phase J3 passed on 2026-07-29 with:

```sh
scripts/probe-windows-java-j3-jit.sh
```

Terminal marker:

`VKMT_WINDOWS_JAVA_J3_JIT_OK`

## Single-prefix lane order

One fresh prefix ran:

1. x86_64 Server VM with tiered compilation;
2. x86_64 Server VM with scoped `-Xcomp`;
3. i386 Client VM/C1 with a low compilation threshold;
4. i386 Client VM with scoped `-Xcomp`.

The scoped compile policy targets `VkmtWindowsJavaJitProbe` and each isolated
`vkmt.dynamic.JitPayload`. In forced mode, only the `main`,
class-loader/reflection, and exception-catching coordinator methods stay
interpreted. Tiered mode owns uncommon-trap and exception-resume acceptance;
forced mode independently proves compile-on-first-use and execution.

## Compilation and code cache

HotSpot `PrintCompilation` recorded nonzero fixture method counts:

- x86_64 tiered: 26
- x86_64 `-Xcomp`: 124
- i386 C1: 27
- i386 `-Xcomp`: 23

The corresponding compilation times were 673 ms, 906 ms, 129 ms, and 45 ms.
Every lane printed a nonempty code-cache summary.

Both tiered lanes passed hot-loop compilation, monomorphic-to-polymorphic
deoptimization, and return to the monomorphic path. Every lane ran four
isolated class-loader waves; each payload was compiled, released, unloaded,
and replaced without stale guest code.

## Executable-memory boundary

Architecture-matched PE32+ and PE32 JNI DLLs repeatedly:

- allocated a private RW page;
- emitted a six-byte x86/x86_64 function;
- changed the page to RX and flushed it;
- executed and verified it;
- changed it to RW, patched the return value, flushed it, and repeated.

Each lane passed 257 protection transitions/flushes and 128 replacement-code
executions. The JNI fixture hashes are retained in `RESULTS.txt`.

## Exceptions and resumption

The tiered lanes compiled the divide, null-check, and recursive methods before
the exception gate. They passed explicit divide-by-zero and null exception
guards, recursive `StackOverflowError`, catches, and execution after each
exception. Forced mode uses the tiered exception result and does not compile
the exception-catching coordinator.

## Provider state and cleanup

The J0 i386 candidate remained
`f7ace1980b33e270c9ee8b9d240705a82bcface99e868ff65895a3dbcfd4d247`.
The J3 x86_64 side candidate is:

`3c5878816c78dc670190e3587e76ace53e472c14a50972cd97808fda25636c3b`

It validates guest bytes before cached-block entry, invalidates cached code on
free/unmap, and provides `VKMT_X64_TIER0=0`. J3 selects that precise outer
lane while HotSpot JIT itself remains enabled. Neither candidate was
promoted.

The exact wineserver stopped and waited. No Java/Wine process or J3 prefix
remains, and both accepted provider copies retained their golden hashes.
Machine-readable results and per-lane compilation telemetry are beside this
file.
