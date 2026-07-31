# Phase 2 final-provider Phase 1 regression

Status: **PASS**

The exact Phase 2 v15 x86_64 and i386 providers passed the complete Phase 1
suite in one fresh prefix with all FEX TSO settings disabled and Steam wake
recovery disabled.

```text
NO_TSO_PHASE1_X64_ORDERING_OK
NO_TSO_PHASE1_X64_WAIT_OK
NO_TSO_PHASE1_X64_CONDITION_OK
NO_TSO_PHASE1_X64_APC_OK
NO_TSO_PHASE1_X64_THREADS_OK
NO_TSO_PHASE1_X64_CHILDREN_OK
NO_TSO_PHASE1_I386_ORDERING_OK
NO_TSO_PHASE1_I386_WAIT_OK
NO_TSO_PHASE1_I386_CONDITION_OK
NO_TSO_PHASE1_I386_APC_OK
NO_TSO_PHASE1_I386_THREADS_OK
NO_TSO_PHASE1_I386_CHILDREN_OK
NO_TSO_PHASE1_X64_CDN_OK
NO_TSO_PHASE1_I386_CDN_OK
NO_TSO_PHASE1_ALL_OK
x64_children=128/128
i386_children=128/128
x64_cdn=8/8
i386_cdn=8/8
cdn_bytes_each=4194304
```

Every CDN output matched SHA-256
`6c12394e835d27f53cf1df56807ed480a86cd07cce1546eef3a01d1886bd4fbe`.
`status.txt` is `0`; exact wineserver shutdown completed and the disposable
prefix was removed.
