# VKMT compatibility expansion plan

The accepted graphics/runtime baseline remains fixed: ARM64, ARM64EC,
x86_64, and i386/WoW64 execute in one prefix; VKMT, DXMT, SDL2/3, OpenGL
2.1/GLSL 1.20, and Metal-backed GLSL 3.30/4.50 gates pass. The work below
adds application compatibility without reopening that baseline.

Every phase must use source or pinned redistributable inputs stored in the
VKMT tree, targeted component builds, ARM64-only host Mach-O, exact-prefix
wineserver shutdown, and disposable-prefix cleanup.

## Phase A — relocatable host dependency closure

1. Stage GnuTLS 3 and its complete ARM64 dylib closure beside Wine:
   `libgnutls`, gettext/libintl, p11-kit/libffi, libidn2, libunistring,
   libtasn1, nettle/hogweed, and GMP.
2. Rewrite every non-system dependency to `@loader_path`; remove Homebrew
   runtime paths; sign each staged Mach-O artifact.
3. Apply the same closure audit to enabled Fontconfig, CUPS, ODBC, SDL2,
   GStreamer/FFmpeg, and MoltenVK consumers.
4. Gate the native ARM64 Wine server/provider path through Schannel
   credentials, WinHTTP and WinINet HTTPS, certificate validation, staged
   GnuTLS load evidence, and a no-Homebrew-path `otool -L` audit. Guest
   architecture HTTPS runs are optional diagnostics, not Phase A gates,
   because the server/Unix provider is native ARM64.

## Phase B — input and game-device compatibility

1. **Complete (2026-07-28):** Wine's in-tree XInput
   1.1/1.2/1.3/1.4/9.1.0/UAP modules and DirectInput/DirectInput8 pass in one
   prefix for ARM64, ARM64EC, x86_64, and i386/WoW64. The native provider is
   the source-built ARM64 `winebus.so` IOHID backend; no Rosetta or guest
   Mach-O is involved.
2. Integrate the MetalSharp GameController-backed ARM64 `xinput1_4` host shim
   only where it extends Wine's macOS driver; do not replace newer Wine PE
   modules with packaged copies.
3. Gate controller enumeration, connect/disconnect, buttons, axes, triggers,
   vibration, multiple controllers, DirectInput keyboard/mouse, Raw Input,
   HID, and force-feedback behavior. The hardware-independent API/provider,
   keyboard, and mouse gates pass. A live-controller session is still required
   to claim physical buttons/axes, hotplug, vibration, and force feedback;
   the probe reports this distinction explicitly.

## Phase C — installers and package engines

1. MSI: **core lifecycle complete (2026-07-28)** for ARM64, ARM64EC, x86_64,
   and i386/WoW64: install, deliberate file corruption, repair, registry and
   embedded-cabinet payload validation, then uninstall. Upgrade, rollback,
   environment actions, services, shortcuts, and custom actions remain.
2. WiX: **fixture generation complete (2026-07-28)** for both 32-bit and
   64-bit packages with native ARM64 `wixl`; the packages are validated through
   Wine's MSI APIs. Direct `msiexec` and `msidb` CLI gates remain.
3. NSIS: build silent and interactive fixtures and prove install/uninstall.
4. Inno Setup: prove ordinary Wine execution plus the native ARM64
   `innoextract` fallback used by MetalSharp for incompatible bootstrappers.
5. Add Squirrel/Electron, InstallShield, Burn/bootstrapper, ClickOnce, MSIX,
   and AppX detection. Unsupported package types must fail diagnostically,
   never hang or leak prefixes.

## Phase D — browser and launcher engines

1. Pin Wine Gecko 2.47.4 x86 and x86_64 packages, stage them in-tree, and
   prove `mshtml` document creation, JavaScript, HTTPS, DOM events, and
   navigation without a download prompt.
2. Integrate MetalSharp's source-preserved CEF compatibility wrapper and
   child-process hook for i386 and x86_64 launchers.
3. Gate CEF `libcef.dll` loading, browser/renderer/GPU subprocess creation,
   sandbox-disabled compatibility mode, offscreen rendering, input, audio,
   HTTPS, and clean child teardown.
4. Add a WebView2 fixed-runtime lane; prove Evergreen-style installers and
   WebView2-based launchers separately from CEF.
5. Cover Electron launchers and common embedded-browser launch patterns.

## Phase E — managed and language runtimes

1. Extract the signed/notarized Oracle JRE 8u501 ARM64 payload from the local
   DMG into a pinned native-Java stage. Preserve license/provenance and do not
   silently redistribute it outside the user's private runtime.
2. Gate native `java -version`, class execution, JAR launch, JNI, JavaFX,
   networking/TLS, audio, and launcher handoff from a Wine bottle.
3. Add separately pinned Windows JRE/JDK i386 and x86_64 lanes for applications
   that require Windows JNI DLLs; a macOS JRE cannot satisfy that ABI.
4. Stage and gate Wine Mono, .NET Framework 3.5/4.8, modern .NET Desktop
   Runtime, PowerShell-hosted installer actions, and common VC++ runtimes.
5. Add opt-in Python and Node.js Windows runtime fixtures for launchers that
   embed those engines.

## Phase F — common game/application redistributables

Stage from pinned, licensed redistributable inputs and gate:

- D3DCompiler plus XAudio/XACT redistributables. Legacy D3DX9/10/11
  compatibility packages are intentionally out of scope.
- Visual C++ 2005 through 2022, UCRT, ATL, and MFC.
- XNA 3.1/4.0, FAudio/FNA, OpenAL, PhysX, and common media codecs.
- MSXML, core fonts, DirectShow/Media Foundation, Quartz, MIDI, and
  GStreamer-backed audio/video playback.

Each component needs detection, idempotent installation, repair, and
architecture-aware staging; presence of an installer is not an acceptance
result.

## Phase G — enterprise and peripheral services

Gate LDAP, Kerberos/GSSAPI, NTLM, ODBC, CUPS printing, smart-card/PCSC,
USB/HID, serial ports, scanners/cameras where macOS exposes them, COM/DCOM,
services, scheduled tasks, shell associations, and certificate-root updates.

## Final acceptance

One fresh prefix must pass:

1. Native ARM64 wineboot and baseline architecture/graphics regressions.
2. XInput/DInput and audio/media fixtures.
3. MSI/WiX, NSIS, and Inno install/uninstall fixtures.
4. Gecko/MSHTML, CEF, WebView2, and Electron launcher fixtures.
5. Native-Java handoff plus Windows Java and .NET fixtures.
6. HTTPS through staged GnuTLS with no Homebrew dependency.
7. Exact wineserver/child-process shutdown and cleanup.

Kernel anti-cheat, kernel DRM, Windows Store identity/licensing, and arbitrary
Windows kernel drivers remain application-specific boundaries. They must be
reported honestly rather than hidden behind a broad compatibility claim.
