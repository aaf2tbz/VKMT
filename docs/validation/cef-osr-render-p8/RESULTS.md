# CEF OSR text/pixel contract — P8

Prefix: `/Volumes/AverySSD/VKMT/build/probe-runs/phase-a-graphics-prefix`

The canonical CEF OSR run passed with the existing prefix and no wineboot.
The data-URL receipt is `browser-20260803T145531.log`; the HTTPS trust
receipt is `browser-20260803T145856.log`.
The browser log contains:

- `VKMT_BROWSER_LOAD_END` / `VKMT_BROWSER_LOAD_STATUS_OK`
- `VKMT_BROWSER_TEXT_OK` from `cef_frame_t::get_text`
- `VKMT_BROWSER_PAINT_BGRA_51_34_17_255`
- `VKMT_BROWSER_TEXT_PIXEL_OK`
- `VKMT_BROWSER_PIXEL_OK`

The host now waits for both the deterministic DOM text marker and foreground
text pixels before quitting. `--ignore-certificate-errors` is opt-in through
`VKMT_BROWSER_IGNORE_CERT_ERRORS=1`; it is not part of the normal CEF launch.

## CEF HTTPS trust fixture

`VKMT_CEF_OSR_HTTPS_TRUST=1 scripts/probe-cef-osr-render.sh` generated a
local root and a `localhost` SAN leaf, installed only the root into the
current-user Windows ROOT store using the ARM64 trust helper, and served
`/index.html` from a local OpenSSL HTTPS server. The browser URL was
`https://localhost:53959/index.html`.

The run returned `status=0` and emitted all of:

- `TLS_ROOT_INSTALL_OK` and cleanup `TLS_ROOT_REMOVE_OK`;
- `VKMT_BROWSER_LOAD_STATUS_OK`;
- `VKMT_BROWSER_TEXT_OK`;
- `VKMT_BROWSER_PAINT_BGRA_51_34_17_255`;
- `VKMT_BROWSER_TEXT_PIXEL_OK` and `VKMT_BROWSER_PIXEL_OK`;
- `CEF_X86_64_OSR_HTTPS_TRUST_OK`.

No certificate-ignore flag was set. The local root, leaf, key, and server
process are temporary and are not package assets. The compact capability table
is `capability.tsv`; the latest HTTPS run status is `status.txt`.
