# WinSock contract — P8

Prefix: `/Volumes/AverySSD/VKMT/build/probe-runs/phase-a-graphics-prefix`

The fixture uses only loopback and `localhost`; it performs no external DNS or network access.

**Result:** all four architecture processes completed with rc=0.

## Capability table

| Architecture | API | Status | Error | Detail |
|---|---|---|---|---|
| arm64 | ipv4_loopback | PASS | 0 | loopback send/recv |
| arm64 | ipv6_loopback | PASS | 0 | loopback send/recv |
| arm64 | dns_localhost | PASS | 0 | offline localhost address enumeration |
| arm64 | SIO_ADDRESS_LIST_SORT | PASS | 0 | IPv4 before IPv6 |
| arm64 | nonblocking_connect | PASS | 0 | FIONBIO plus writable completion |
| arm64 | select | PASS | 0 | read readiness |
| arm64 | WSAPoll | PASS | 0 | read readiness |
| arm64 | WSAEventSelect_rearm | PASS | 0 | event notification and rearm |
| arm64 | overlapped_iocp | PASS | 0 | WSARecv completion port |
| arm64 | parallel_close | PASS | 0 | parallel connections and close races |
| arm64ec | ipv4_loopback | PASS | 0 | loopback send/recv |
| arm64ec | ipv6_loopback | PASS | 0 | loopback send/recv |
| arm64ec | dns_localhost | PASS | 0 | offline localhost address enumeration |
| arm64ec | SIO_ADDRESS_LIST_SORT | PASS | 0 | IPv4 before IPv6 |
| arm64ec | nonblocking_connect | PASS | 0 | FIONBIO plus writable completion |
| arm64ec | select | PASS | 0 | read readiness |
| arm64ec | WSAPoll | PASS | 0 | read readiness |
| arm64ec | WSAEventSelect_rearm | PASS | 0 | event notification and rearm |
| arm64ec | overlapped_iocp | PASS | 0 | WSARecv completion port |
| arm64ec | parallel_close | PASS | 0 | parallel connections and close races |
| x86_64 | ipv4_loopback | PASS | 0 | loopback send/recv |
| x86_64 | ipv6_loopback | PASS | 0 | loopback send/recv |
| x86_64 | dns_localhost | PASS | 0 | offline localhost address enumeration |
| x86_64 | SIO_ADDRESS_LIST_SORT | PASS | 0 | IPv4 before IPv6 |
| x86_64 | nonblocking_connect | PASS | 0 | FIONBIO plus writable completion |
| x86_64 | select | PASS | 0 | read readiness |
| x86_64 | WSAPoll | PASS | 0 | read readiness |
| x86_64 | WSAEventSelect_rearm | PASS | 0 | event notification and rearm |
| x86_64 | overlapped_iocp | PASS | 0 | WSARecv completion port |
| x86_64 | parallel_close | PASS | 0 | parallel connections and close races |
| i386 | ipv4_loopback | PASS | 0 | loopback send/recv |
| i386 | ipv6_loopback | PASS | 0 | loopback send/recv |
| i386 | dns_localhost | PASS | 0 | offline localhost address enumeration |
| i386 | SIO_ADDRESS_LIST_SORT | UNSUPPORTED | 10045 | provider does not expose address-list sorting |
| i386 | nonblocking_connect | PASS | 0 | FIONBIO plus writable completion |
| i386 | select | PASS | 0 | read readiness |
| i386 | WSAPoll | PASS | 0 | read readiness |
| i386 | WSAEventSelect_rearm | PASS | 0 | event notification and rearm |
| i386 | overlapped_iocp | PASS | 0 | WSARecv completion port |
| i386 | parallel_close | PASS | 0 | parallel connections and close races |

## Scope

- IPv4/IPv6 loopback, offline localhost address enumeration, and address ordering.
- Nonblocking connect/SO_ERROR, select, WSAPoll, WSAEventSelect notification/rearm.
- Overlapped WSARecv with IOCP completion lifetime and parallel connect/send/close races.
- `UNSUPPORTED` rows are explicit provider capability results and are not silently converted to passes.
- TLS trust, fragmentation, proxy, COM, callback, and DirectWrite contracts are separate gates.

Environment: FEX_TSOENABLED=0, FEX_VECTORTSOENABLED=0, FEX_MEMCPYSETTSOENABLED=0, wineboot=not-run.
