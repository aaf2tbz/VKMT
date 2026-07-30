# Windows Java phase J4 acceptance

Phase J4 passed on 2026-07-29 with:

```text
VKMT_WINDOWS_JAVA_J4_MEMORY_MODEL_OK
```

The accepted i386 provider was tested first and selected:

```text
ea523a42ca8e7965371122bd7be1eb6b973cded50ecda5da1465b2961ad36479
```

The side candidate remained unpromoted and was not needed for acceptance.
Before any JVM launch, its focused FEX fixture still passed the mandatory
software-TSO disassembly gate: aligned accesses emitted `LDAR`/`STLR`,
unaligned loads emitted `LDR` plus `DMB ISHLD`, unaligned stores emitted
`DMB ISH` plus `STR`, locked RMW used acquire/release atomics, no
`LDAPR`/`LDAPUR` appeared, and Windows FEX did not enable host hardware TSO.

## Runtime gate

Three independent high-load repetitions each used a fresh prefix. Every
prefix ran two i386 Client VM processes:

1. A mixed/JIT memory lane covered volatile sequence/payload publication,
   contended monitor enter/exit and wait/notify, `AtomicInteger`,
   `AtomicLong`/`cmpxchg8b`, concurrent queue handoff, once initialization,
   deliberately unaligned scalar publication, REP stores, and
   `movntq`/`sfence`.
2. An interpreted allocation/GC lane kept four mutators active while
   allocation-driven young collection occurred, then verified 20,000 linked
   objects, their fields, roots, and pressure-buffer checksums.

All three mixed lanes produced the same values:

```text
publication=4657f8de1200
atomic=9c4000009c40
native=4a34000000004e20
checksum=4a34e29804cae571
```

All three GC lanes produced:

```text
created=20000
seen=20000
valueSum=49990000
pressureSum=2517360
checksum=4e2002dcee20
```

There were three observed allocation-driven GC events. No publication was
missed, no 64-bit atomic tore, no worker deadlocked, and no accepted lane
raised an exception. The JNI fixture is PE32
`IMAGE_FILE_MACHINE_I386`, SHA-256
`380f4ab71824ff779c08dd1836c8b18b49a6c60e856eecd1ba40f300a4016d6c`.

Every prefix's exact wineserver was stopped and waited before that prefix was
deleted. No J4 prefix or Java process remains. The canonical provider and its
build-tree copy remain byte-identical.

## J5 diagnostic carried forward

An intentionally deeper combined experiment ran compiled mutators across
repeated GC safepoints. The accepted provider completed one full semantic
round and one allocation collection, but a subsequent publication could
stall. More aggressive full-GC loops reached repeated `GenCollectFull`
operations before class dispatch failed inside `jvm.dll`; the side candidate
showed the same ownership boundary.

That experiment is not part of J4 acceptance. It is preserved in the
`diagnostic-*` files here because phase J5 explicitly owns GC safepoints while
other threads allocate and execute compiled code, plus repeated VM lifecycle.
J5 must resolve and regress this behavior rather than weakening or silently
discarding it.

Machine-readable results are in `RESULTS.txt`; the pre-JVM prerequisite log
is `j0-tso.log`.
