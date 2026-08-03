# COM, STA, callbacks, and DirectWrite contract — P8

Prefix: `/Volumes/AverySSD/VKMT/build/probe-runs/phase-a-graphics-prefix`

**Result:** requested architecture processes completed with rc=0.

## Capability table

| Architecture | API | Status | HRESULT | Detail |
|---|---|---|---|---|
| arm64 | COM_STA | PASS | 0x00000001 | main STA initialized |
| arm64 | COM_cross_thread_marshal | UNSUPPORTED | 0x80070102 | provider did not complete standard IStream cross-apartment marshal |
| arm64 | STA_message_pump | PASS | 0x00000000 | cross-thread callback delivered |
| arm64 | nested_message_loop | PASS | 0x00000000 | nested callback completed |
| arm64 | controller_environment_completion | PASS | 0x00000000 | completion callback observed before shutdown |
| arm64 | window_lifetime | PASS | 0x00000000 | message-only window destroyed on owner thread |
| arm64 | DirectWrite_font_collection | PASS | 0x00000000 | system fonts enumerated |
| arm64 | DirectWrite_glyphs | PASS | 0x00000000 | Latin and mixed-script glyph indices |
| arm64 | DirectWrite_layout | PASS | 0x00000000 | layout metrics and shaping input accepted |
| arm64 | DirectWrite_fallback | PASS | 0x00000000 | mixed-script fallback mapping |
| arm64ec | COM_STA | PASS | 0x00000001 | main STA initialized |
| arm64ec | COM_cross_thread_marshal | UNSUPPORTED | 0x80070102 | provider did not complete standard IStream cross-apartment marshal |
| arm64ec | STA_message_pump | PASS | 0x00000000 | cross-thread callback delivered |
| arm64ec | nested_message_loop | PASS | 0x00000000 | nested callback completed |
| arm64ec | controller_environment_completion | PASS | 0x00000000 | completion callback observed before shutdown |
| arm64ec | window_lifetime | PASS | 0x00000000 | message-only window destroyed on owner thread |
| arm64ec | DirectWrite_font_collection | PASS | 0x00000000 | system fonts enumerated |
| arm64ec | DirectWrite_glyphs | PASS | 0x00000000 | Latin and mixed-script glyph indices |
| arm64ec | DirectWrite_layout | PASS | 0x00000000 | layout metrics and shaping input accepted |
| arm64ec | DirectWrite_fallback | PASS | 0x00000000 | mixed-script fallback mapping |
| x86_64 | COM_STA | PASS | 0x00000001 | main STA initialized |
| x86_64 | COM_cross_thread_marshal | UNSUPPORTED | 0x80070102 | provider did not complete standard IStream cross-apartment marshal |
| x86_64 | STA_message_pump | PASS | 0x00000000 | cross-thread callback delivered |
| x86_64 | nested_message_loop | PASS | 0x00000000 | nested callback completed |
| x86_64 | controller_environment_completion | PASS | 0x00000000 | completion callback observed before shutdown |
| x86_64 | window_lifetime | PASS | 0x00000000 | message-only window destroyed on owner thread |
| x86_64 | DirectWrite_font_collection | PASS | 0x00000000 | system fonts enumerated |
| x86_64 | DirectWrite_glyphs | PASS | 0x00000000 | Latin and mixed-script glyph indices |
| x86_64 | DirectWrite_layout | PASS | 0x00000000 | layout metrics and shaping input accepted |
| x86_64 | DirectWrite_fallback | PASS | 0x00000000 | mixed-script fallback mapping |
| i386 | COM_STA | PASS | 0x00000001 | main STA initialized |
| i386 | COM_cross_thread_marshal | UNSUPPORTED | 0x80070102 | provider did not complete standard IStream cross-apartment marshal |
| i386 | STA_message_pump | PASS | 0x00000000 | cross-thread callback delivered |
| i386 | nested_message_loop | PASS | 0x00000000 | nested callback completed |
| i386 | controller_environment_completion | PASS | 0x00000000 | completion callback observed before shutdown |
| i386 | window_lifetime | PASS | 0x00000000 | message-only window destroyed on owner thread |
| i386 | DirectWrite_font_collection | PASS | 0x00000000 | system fonts enumerated |
| i386 | DirectWrite_glyphs | PASS | 0x00000000 | Latin and mixed-script glyph indices |
| i386 | DirectWrite_layout | UNSUPPORTED | 0x80004005 | provider returned no positive mixed-script layout metrics |
| i386 | DirectWrite_fallback | PASS | 0x00000000 | mixed-script fallback mapping |

## Scope

- COM STA initialization and standard IStream cross-apartment marshaling.
- STA message pumping, cross-thread callback delivery, nested SendMessage callback, completion ordering, and window destruction.
- DirectWrite factory/font collection enumeration, family/font-face lookup, glyph lookup, mixed-script text layout, and system fallback MapCharacters.
- `UNSUPPORTED` rows are explicit known provider gaps; they are not reported as passes.
- CEF/WebView actual text/pixel output is a separate browser evidence gate.
- Font source candidates `dlls/dwrite/freetype.c` and `dlls/win32u/freetype.c` are not changed by this fixture.

Environment: FEX_TSOENABLED=0, FEX_VECTORTSOENABLED=0, FEX_MEMCPYSETTSOENABLED=0, wineboot=not-run.
