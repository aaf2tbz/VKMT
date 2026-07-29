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

## Phase B — input and game-device compatibility — COMPLETE (2026-07-28)

1. Wine's in-tree XInput
   1.1/1.2/1.3/1.4/9.1.0/UAP modules and DirectInput/DirectInput8 pass in one
   prefix for ARM64, ARM64EC, x86_64, and i386/WoW64. The native provider is
   the source-built ARM64 `winebus.so` SDL backend with its pinned, relocatable
   ARM64 SDL2 provider; no Rosetta or guest Mach-O is involved.
2. A physical PS5 DualSense passes normalized XInput enumeration/state,
   live-axis activity, force-feedback capability, and nonzero vibration calls
   in all four guest modes. DirectInput/DirectInput8 controller enumeration
   and keyboard/mouse enumeration also pass.
3. SDL is authoritative for game controllers on macOS during the acceptance
   run; raw IOHID joystick enumeration is disabled to prevent duplicate,
   unnormalized devices. The newer Wine PE modules remain authoritative, so
   no packaged MetalSharp XInput DLL replaces them.
4. Multiple-controller and disconnect/reconnect exercises remain optional
   hardware-coverage extensions, not blockers for the completed single-pad
   phase.

## Phase C — installers and package engines

**Complete (2026-07-28).**

1. MSI's core install/corrupt/repair/uninstall lifecycle passes ARM64,
   ARM64EC, x86_64, and i386/WoW64 in one prefix. Native ARM64 `msiexec` and
   `msidb` additionally pass WiX upgrades, environment rows, registry rows,
   shortcuts, and service-table processing. Guest CLI modes remain optional
   diagnostics because the all-architecture contract is the MSI API fixture.
2. Native ARM64 `wixl` reproducibly builds both 32-bit and 64-bit core
   packages plus versioned extended packages.
3. The i386 NSIS fixture passes silent installation, payload execution,
   uninstall-section cleanup, and registry removal.
4. Inno Setup 6.3.3's real i386 `ISCC.exe` executes through WoW64 and compiles
   the deterministic fixture. The pinned, relocatable native ARM64
   `innoextract` closure recovers and byte-validates its payload. Inno 6.5.4
   is pinned and classified, but its GUI setup transaction is not claimed;
   packages use the extraction fallback when direct execution is unsuitable.
5. The read-only classifier recognizes MSI, Inno, NSIS, WiX Burn,
   InstallShield, Squirrel, ClickOnce, MSIX, and AppX families. Unsupported
   engines return a bounded diagnostic failure and never create a prefix.

Evidence: `docs/validation/installer-completion-20260728/RESULTS.md`.

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

Status (2026-07-29): the private Oracle JRE 8u501 ARM64 payload is pinned and
staged. Official Wine Mono 11.2.0 is pinned from GitHub, its x86 and x86_64
engines are preserved unchanged, and a source-built ARM64 engine is integrated
with the VKMT ABI/W^X contract. Wine's process, Unix loader, Windows loader,
and server image-view paths now agree that same-bitness PE32+ IL-only images
use the native 64-bit CLR rather than starting `xtajit64`. One disposable
prefix passes managed compile and direct execution gates for ARM64, x86_64,
and i386, followed by the ordinary ARM64/ARM64EC/x86_64/i386 single-prefix
regression. Native-Java breadth, Windows Java, .NET Framework/modern
.NET/PowerShell, and opt-in Python/Node remain.

## Phase F — common game/application redistributables

**Closed by scope decision (2026-07-29).**

The current Wine build already contains the desired D3DCompiler,
XAudio2/XACT, UCRT/Visual C++/ATL, MSXML, Quartz, Media Foundation, MIDI,
WineGStreamer, and Windows codec modules. XNA/FNA and FAudio assets are
preserved through MetalSharp. No additional Phase F staging, probing, or
validation is required. Legacy D3DX9/10/11, MFC, OpenAL, PhysX, and additional
core-font payload work are outside the completion roadmap.

There is no Phase G. Enterprise services and additional peripheral coverage
are explicitly outside this runtime's completion roadmap.

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
