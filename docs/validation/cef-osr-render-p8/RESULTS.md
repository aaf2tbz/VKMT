# CEF OSR text/pixel contract — P8

Prefix: `/Volumes/AverySSD/VKMT/build/probe-runs/phase-a-graphics-prefix`

The canonical CEF OSR run passed with the existing prefix and no wineboot.
Receipt: `browser-20260803T143019.log`.
The browser log contains:

- `VKMT_BROWSER_LOAD_END` / `VKMT_BROWSER_LOAD_STATUS_OK`
- `VKMT_BROWSER_TEXT_OK` from `cef_frame_t::get_text`
- `VKMT_BROWSER_PAINT_BGRA_51_34_17_255`
- `VKMT_BROWSER_TEXT_PIXEL_OK`
- `VKMT_BROWSER_PIXEL_OK`

The host now waits for both the deterministic DOM text marker and foreground
text pixels before quitting. `--ignore-certificate-errors` is opt-in through
`VKMT_BROWSER_IGNORE_CERT_ERRORS=1`; it is not part of the normal CEF launch.
