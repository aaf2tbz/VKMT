# VKMT Steam handoff backend

This is a loopback-only HTTP receiver for the two Steam bootstrap handoffs.
It binds `127.0.0.1:9274` and never enables TSO.

Endpoints:

- `GET /status` reports the accepted-cycle count and active operation.
- `POST /steam/handoff` acknowledges one handoff, shuts down only the Phase 6
  prefix's wineserver, and launches its installed `Steam.exe`. Exactly two
  handoffs are accepted per backend lifetime; concurrent and excess requests
  are rejected.
- `POST /reset` resets the counter only while no handoff is active.

Build and run:

```sh
cargo build --release --manifest-path tools/steam-handoff-backend/Cargo.toml
nohup build/steam-handoff-backend >logs/steam-handoff-backend-host.log 2>&1 &
curl http://127.0.0.1:9274/status
```

The notification contract is:

```http
POST /steam/handoff HTTP/1.1
Host: 127.0.0.1:9274
Content-Length: 0
```

The native ARM64 ntdll Unix file path emits this request once per Steam
process when a successful write contains the complete marker
`Update complete, launching Steam...`. The hook is disabled unless
`VKMT_STEAM_HANDOFF_NOTIFY=1`; `VKMT_STEAM_HANDOFF_PORT` may override port
9274 for isolated tests.
