# No-TSO Rosetta-parity Phase 4 results

Status: **PASS**

`scripts/probe-no-tso-phase4.sh` passed the asynchronous networking gate for
x86_64 and i386 in one clean prefix with the accepted Phase 2 providers and
Phase 3 wait bridge.

All accepted execution used:

```text
FEX_TSOENABLED=0
FEX_VECTORTSOENABLED=0
FEX_MEMCPYSETTSOENABLED=0
VKMT_STEAM_BOOTSTRAP_WAKE_RECOVERY=0
```

## Coverage

- Eight simultaneous callback-driven WinHTTP HTTPS range requests per guest
  architecture.
- A shared WinHTTP connection, exercising connection pooling/reuse.
- Partial `DATA_AVAILABLE` and `READ_COMPLETE` callbacks until exact byte
  commit.
- Slot zero downloads two consecutive 2 MiB ranges through separate requests
  on the shared connection, proving range restart and append.
- The other seven slots each download the full 4 MiB range.
- Request submission, callback queue/consumption, socket readability, byte
  receipt, and package commit are traced explicitly.
- A loopback overlapped Winsock fixture associates the client socket with an
  IO completion port, receives data, posts the next receive, observes peer
  shutdown as a zero-byte completion, and joins the server worker cleanly.

## Results

```text
NO_TSO_PHASE4_X64_ASYNC_CDN_OK
NO_TSO_PHASE4_I386_ASYNC_CDN_OK
NO_TSO_PHASE4_IOCP_PEER_CLOSE_OK   (both architectures)
NO_TSO_PHASE4_ASYNC_NETWORK_OK
x64_downloads=8/8
i386_downloads=8/8
bytes_each=4194304
```

Every output is exactly 4,194,304 bytes and matches the native reference
SHA-256 `6c12394e835d27f53cf1df56807ed480a86cd07cce1546eef3a01d1886bd4fbe`.
All HTTP responses were validated as 206 with the exact range length; no HTTP
200 or zero-byte success was accepted.

The initial v1/v2 diagnostic attempts used the wrong WinHTTP callback mask in
the new fixture and were rejected and cleaned. The corrected v3 synchronous
range pass and final v5 range-restart/IOCP pass completed without Wine source
changes. `status.txt` is `0`; exact wineserver shutdown completed, the
disposable prefix was deleted, and canonical bootstrap providers were restored.
