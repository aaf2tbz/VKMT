# CEF x86_64 final P8 gate

The user-facing CEF OSR host was rebuilt from the current source and launched
against the same canonical prefix used by the architecture gate. No prefix
recreation or Wineboot was performed. All FEX TSO controls were zero.

Acceptance markers:

- `VKMT_BROWSER_ENTRY`
- `VKMT_BROWSER_CONTEXT_INITIALIZED`
- `VKMT_BROWSER_INITIALIZE_RETURNED`
- `VKMT_BROWSER_CREATED`
- `VKMT_BROWSER_PAINT_BGRA_51_34_17_255`
- `VKMT_BROWSER_PIXEL_OK`
- `VKMT_BROWSER_CLOSED`

The launcher returned `rc=0`. i386/WoW64 CEF is intentionally outside this
final gate and remains recorded as an open diagnostic gap separately.
