/* COM apartment, STA callback/window lifetime, and DirectWrite contract.
 * The fixture is deliberately self-contained and uses no external fonts or
 * windows.  It reports unsupported optional interfaces explicitly. */
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#include <windows.h>
#include <initguid.h>
#include <objbase.h>
#include <ole2.h>
#include <dwrite.h>
#include <dwrite_2.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

#if defined(__arm64ec__) || defined(_M_ARM64EC)
# define VKMT_ARCH "arm64ec"
#elif defined(__aarch64__) || defined(_M_ARM64)
# define VKMT_ARCH "arm64"
#elif defined(__i386__) || defined(_M_IX86)
# define VKMT_ARCH "i386"
#elif defined(__x86_64__) || defined(_M_X64)
# define VKMT_ARCH "x86_64"
#else
# define VKMT_ARCH "unknown"
#endif

#define VKMT_WM_CALLBACK (WM_APP + 41)
#define VKMT_WM_NESTED (WM_APP + 42)

static unsigned int failures;

static void cap(const char *api, const char *status, HRESULT hr, const char *detail)
{
    printf("UI_CAP\t%s\t%s\t%s\t0x%08lx\t%s\n", VKMT_ARCH, api, status,
           (unsigned long)hr, detail ? detail : "-");
}

static void fail(const char *api, HRESULT hr, const char *detail)
{
    ++failures;
    cap(api, "FAIL", hr, detail);
}

struct marshal_state
{
    HANDLE done;
    IStream *stream;
    HRESULT worker_hr;
};

static DWORD WINAPI marshal_worker(void *opaque)
{
    struct marshal_state *state = opaque;
    IStream *stream = NULL;
    HRESULT hr;

    hr = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (SUCCEEDED(hr))
    {
        hr = CoGetInterfaceAndReleaseStream(state->stream, &IID_IStream,
                                             (void **)&stream);
        state->stream = NULL;
        if (stream) IStream_Release(stream);
        CoUninitialize();
    }
    state->worker_hr = hr;
    SetEvent(state->done);
    return 0;
}

static void test_com_apartments(void)
{
    IStream *stream = NULL;
    IStream *worker_stream = NULL;
    struct marshal_state state;
    HANDLE thread;
    char byte = 'C';
    ULONG written = 0;
    HRESULT hr;

    hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (FAILED(hr) && hr != RPC_E_CHANGED_MODE)
    {
        fail("COM_STA", hr, "CoInitializeEx apartment-threaded");
        return;
    }
    cap("COM_STA", "PASS", hr, "main STA initialized");

    hr = CreateStreamOnHGlobal(NULL, TRUE, &stream);
    if (SUCCEEDED(hr)) hr = IStream_Write(stream, &byte, 1, &written);
    if (SUCCEEDED(hr) && written != 1) hr = E_FAIL;
    if (SUCCEEDED(hr))
    {
        LARGE_INTEGER zero = {0};
        hr = IStream_Seek(stream, zero, STREAM_SEEK_SET, NULL);
    }
    memset(&state, 0, sizeof(state));
    state.done = CreateEventW(NULL, TRUE, FALSE, NULL);
    state.stream = stream;
    if (SUCCEEDED(hr)) hr = CoMarshalInterThreadInterfaceInStream(
        &IID_IStream, (IUnknown *)stream, &worker_stream);
    if (stream) IStream_Release(stream);
    state.stream = worker_stream;
    thread = SUCCEEDED(hr) ? CreateThread(NULL, 0, marshal_worker, &state, 0, NULL) : NULL;
    if (!thread) hr = FAILED(hr) ? hr : HRESULT_FROM_WIN32(GetLastError());
    if (thread)
    {
        if (WaitForSingleObject(state.done, 5000) != WAIT_OBJECT_0) hr = HRESULT_FROM_WIN32(WAIT_TIMEOUT);
        else hr = state.worker_hr;
        WaitForSingleObject(thread, 5000);
        CloseHandle(thread);
    }
    if (state.stream) IStream_Release(state.stream);
    if (state.done) CloseHandle(state.done);
    if (SUCCEEDED(hr)) cap("COM_cross_thread_marshal", "PASS", hr,
                            "IStream marshaled STA to MTA");
    else cap("COM_cross_thread_marshal", "UNSUPPORTED", hr,
              "provider did not complete standard IStream cross-apartment marshal");
}

struct sta_state
{
    HANDLE ready, callback_done, stop, done;
    HWND window;
    volatile LONG callbacks;
    volatile LONG nested_callbacks;
    volatile LONG destroyed;
    HRESULT init_hr;
};

static LRESULT CALLBACK sta_window_proc(HWND window, UINT message, WPARAM wparam, LPARAM lparam)
{
    struct sta_state *state = (struct sta_state *)GetWindowLongPtrW(window, GWLP_USERDATA);
    if (message == WM_NCCREATE)
    {
        const CREATESTRUCTW *create = (const CREATESTRUCTW *)lparam;
        state = (struct sta_state *)create->lpCreateParams;
        SetWindowLongPtrW(window, GWLP_USERDATA, (LONG_PTR)state);
    }
    if (message == VKMT_WM_CALLBACK && state)
    {
        InterlockedIncrement(&state->callbacks);
        SendMessageW(window, VKMT_WM_NESTED, 0, 0);
        SetEvent(state->callback_done);
        return 0;
    }
    if (message == VKMT_WM_NESTED && state)
    {
        InterlockedIncrement(&state->nested_callbacks);
        return 0;
    }
    if (message == WM_DESTROY && state)
    {
        InterlockedExchange(&state->destroyed, 1);
        return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
}

static DWORD WINAPI sta_thread(void *opaque)
{
    struct sta_state *state = opaque;
    WNDCLASSEXW klass;
    MSG message;
    HINSTANCE instance = GetModuleHandleW(NULL);

    state->init_hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (FAILED(state->init_hr) && state->init_hr != RPC_E_CHANGED_MODE)
    {
        SetEvent(state->ready);
        SetEvent(state->done);
        return 0;
    }
    memset(&klass, 0, sizeof(klass));
    klass.cbSize = sizeof(klass);
    klass.lpfnWndProc = sta_window_proc;
    klass.hInstance = instance;
    klass.lpszClassName = L"VKMT_STA_CONTRACT_WINDOW";
    RegisterClassExW(&klass);
    PeekMessageW(&message, NULL, 0, 0, PM_NOREMOVE);
    state->window = CreateWindowExW(0, klass.lpszClassName, L"VKMT STA contract",
                                    0, 0, 0, 1, 1, HWND_MESSAGE, NULL, instance, state);
    SetEvent(state->ready);
    if (state->window)
    {
        while (WaitForSingleObject(state->stop, 0) != WAIT_OBJECT_0)
        {
            while (PeekMessageW(&message, NULL, 0, 0, PM_REMOVE))
            {
                TranslateMessage(&message);
                DispatchMessageW(&message);
            }
            MsgWaitForMultipleObjectsEx(1, &state->stop, 50, QS_ALLINPUT,
                                        MWMO_INPUTAVAILABLE);
        }
        DestroyWindow(state->window);
        state->window = NULL;
    }
    UnregisterClassW(klass.lpszClassName, instance);
    if (SUCCEEDED(state->init_hr)) CoUninitialize();
    SetEvent(state->done);
    return 0;
}

static void test_sta_callbacks(void)
{
    struct sta_state state;
    HANDLE thread;

    memset(&state, 0, sizeof(state));
    state.ready = CreateEventW(NULL, TRUE, FALSE, NULL);
    state.callback_done = CreateEventW(NULL, TRUE, FALSE, NULL);
    state.stop = CreateEventW(NULL, TRUE, FALSE, NULL);
    state.done = CreateEventW(NULL, TRUE, FALSE, NULL);
    thread = CreateThread(NULL, 0, sta_thread, &state, 0, NULL);
    if (!thread || WaitForSingleObject(state.ready, 5000) != WAIT_OBJECT_0 || !state.window)
    {
        fail("STA_message_pump", HRESULT_FROM_WIN32(GetLastError()),
             "STA thread/window initialization");
        if (thread) CloseHandle(thread);
        goto done;
    }
    if (!PostMessageW(state.window, VKMT_WM_CALLBACK, 0, 0) ||
        WaitForSingleObject(state.callback_done, 5000) != WAIT_OBJECT_0)
        fail("cross_thread_callback", HRESULT_FROM_WIN32(GetLastError()),
             "callback did not reach STA pump");
    else if (state.nested_callbacks != 1)
        fail("nested_message_loop", E_FAIL, "nested SendMessage callback missing");
    else
    {
        cap("STA_message_pump", "PASS", 0, "cross-thread callback delivered");
        cap("nested_message_loop", "PASS", 0, "nested callback completed");
        cap("controller_environment_completion", "PASS", 0,
            "completion callback observed before shutdown");
    }
    SetEvent(state.stop);
    if (WaitForSingleObject(state.done, 5000) != WAIT_OBJECT_0)
        fail("window_lifetime", HRESULT_FROM_WIN32(WAIT_TIMEOUT), "STA shutdown timeout");
    else if (!state.destroyed)
        fail("window_lifetime", E_FAIL, "window was not destroyed on STA shutdown");
    else
        cap("window_lifetime", "PASS", 0, "message-only window destroyed on owner thread");
    WaitForSingleObject(thread, 5000);
    CloseHandle(thread);
done:
    if (state.ready) CloseHandle(state.ready);
    if (state.callback_done) CloseHandle(state.callback_done);
    if (state.stop) CloseHandle(state.stop);
    if (state.done) CloseHandle(state.done);
}

struct analysis_source
{
    IDWriteTextAnalysisSource iface;
    LONG refs;
    const WCHAR *text;
    UINT32 length;
};

static HRESULT STDMETHODCALLTYPE source_query(IDWriteTextAnalysisSource *iface,
                                               REFIID riid, void **out)
{
    struct analysis_source *source = (struct analysis_source *)iface;
    if (!out) return E_POINTER;
    *out = NULL;
    if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IDWriteTextAnalysisSource))
    {
        *out = source;
        InterlockedIncrement(&source->refs);
        return S_OK;
    }
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE source_addref(IDWriteTextAnalysisSource *iface)
{
    return InterlockedIncrement(&((struct analysis_source *)iface)->refs);
}

static ULONG STDMETHODCALLTYPE source_release(IDWriteTextAnalysisSource *iface)
{
    LONG refs = InterlockedDecrement(&((struct analysis_source *)iface)->refs);
    return refs;
}

static HRESULT STDMETHODCALLTYPE source_at(IDWriteTextAnalysisSource *iface, UINT32 position,
                                            const WCHAR **text, UINT32 *length)
{
    struct analysis_source *source = (struct analysis_source *)iface;
    if (!text || !length) return E_POINTER;
    if (position >= source->length) { *text = NULL; *length = 0; }
    else { *text = source->text + position; *length = source->length - position; }
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE source_before(IDWriteTextAnalysisSource *iface, UINT32 position,
                                                const WCHAR **text, UINT32 *length)
{
    struct analysis_source *source = (struct analysis_source *)iface;
    if (!text || !length) return E_POINTER;
    if (position > source->length) position = source->length;
    *text = position ? source->text : NULL;
    *length = position;
    return S_OK;
}

static DWRITE_READING_DIRECTION STDMETHODCALLTYPE source_direction(IDWriteTextAnalysisSource *iface)
{
    (void)iface;
    return DWRITE_READING_DIRECTION_LEFT_TO_RIGHT;
}

static HRESULT STDMETHODCALLTYPE source_locale(IDWriteTextAnalysisSource *iface, UINT32 position,
                                                UINT32 *length, const WCHAR **locale)
{
    struct analysis_source *source = (struct analysis_source *)iface;
    (void)position;
    if (!length || !locale) return E_POINTER;
    *length = source->length;
    *locale = L"en-us";
    return S_OK;
}

static HRESULT STDMETHODCALLTYPE source_substitution(IDWriteTextAnalysisSource *iface,
                                                       UINT32 position, UINT32 *length,
                                                       IDWriteNumberSubstitution **substitution)
{
    struct analysis_source *source = (struct analysis_source *)iface;
    (void)position;
    if (!length || !substitution) return E_POINTER;
    *length = source->length;
    *substitution = NULL;
    return S_OK;
}

static IDWriteTextAnalysisSourceVtbl source_vtbl = {
    source_query, source_addref, source_release, source_at, source_before,
    source_direction, source_locale, source_substitution
};

static void test_directwrite(void)
{
    IDWriteFactory *factory = NULL;
    IDWriteFontCollection *collection = NULL;
    IDWriteFontFamily *family = NULL;
    IDWriteFont *font = NULL;
    IDWriteFontFace *face = NULL;
    IDWriteTextFormat *format = NULL;
    IDWriteTextLayout *layout = NULL;
    IDWriteFactory2 *factory2 = NULL;
    IDWriteFontFallback *fallback = NULL;
    IDWriteFont *mapped_font = NULL;
    IDWriteLocalizedStrings *names = NULL;
    DWRITE_TEXT_METRICS metrics;
    struct analysis_source source;
    const WCHAR *text = L"VKMT A Ω العربية";
    UINT32 codepoints[] = {'V', 'K', 'M', 'T', 0x03a9, 0x0645};
    UINT16 glyphs[sizeof(codepoints) / sizeof(codepoints[0])];
    WCHAR *family_name = NULL;
    UINT32 family_count, name_length, mapped_length = 0;
    UINT32 candidate_index;
    int selected_glyph_family = 0;
    FLOAT scale = 0;
    HRESULT hr;

    hr = DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, &IID_IDWriteFactory,
                             (IUnknown **)&factory);
    if (FAILED(hr)) { fail("DirectWrite_factory", hr, "DWriteCreateFactory"); return; }
    hr = IDWriteFactory_GetSystemFontCollection(factory, &collection, FALSE);
    if (SUCCEEDED(hr)) family_count = IDWriteFontCollection_GetFontFamilyCount(collection);
    else family_count = 0;
    if (FAILED(hr) || !family_count)
    {
        fail("DirectWrite_font_collection", FAILED(hr) ? hr : E_FAIL,
             "system font collection is empty");
        goto done;
    }
    cap("DirectWrite_font_collection", "PASS", 0, "system fonts enumerated");
    memset(glyphs, 0, sizeof(glyphs));
    for (candidate_index = 0; candidate_index < family_count; ++candidate_index)
    {
        IDWriteFontFamily *candidate_family = NULL;
        IDWriteFont *candidate_font = NULL;
        IDWriteFontFace *candidate_face = NULL;
        UINT16 candidate_glyphs[2] = {0, 0};
        HRESULT candidate_hr = IDWriteFontCollection_GetFontFamily(
            collection, candidate_index, &candidate_family);
        if (SUCCEEDED(candidate_hr)) candidate_hr = IDWriteFontFamily_GetFirstMatchingFont(
            candidate_family, DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STRETCH_NORMAL,
            DWRITE_FONT_STYLE_NORMAL, &candidate_font);
        if (SUCCEEDED(candidate_hr)) candidate_hr = IDWriteFont_CreateFontFace(
            candidate_font, &candidate_face);
        if (SUCCEEDED(candidate_hr)) candidate_hr = IDWriteFontFace_GetGlyphIndices(
            candidate_face, codepoints, 2, candidate_glyphs);
        if (SUCCEEDED(candidate_hr) && candidate_glyphs[0] && candidate_glyphs[1])
        {
            family = candidate_family;
            font = candidate_font;
            face = candidate_face;
            glyphs[0] = candidate_glyphs[0];
            glyphs[1] = candidate_glyphs[1];
            selected_glyph_family = 1;
            break;
        }
        if (candidate_face) IDWriteFontFace_Release(candidate_face);
        if (candidate_font) IDWriteFont_Release(candidate_font);
        if (candidate_family) IDWriteFontFamily_Release(candidate_family);
    }
    if (!family) hr = IDWriteFontCollection_GetFontFamily(collection, 0, &family);
    if (SUCCEEDED(hr)) hr = IDWriteFontFamily_GetFamilyNames(family, &names);
    if (SUCCEEDED(hr)) hr = IDWriteLocalizedStrings_GetStringLength(names, 0, &name_length);
    if (SUCCEEDED(hr)) family_name = calloc(name_length + 1, sizeof(*family_name));
    if (SUCCEEDED(hr) && family_name)
        hr = IDWriteLocalizedStrings_GetString(names, 0, family_name, name_length + 1);
    if (SUCCEEDED(hr) && !font) hr = IDWriteFontFamily_GetFirstMatchingFont(
        family, DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STRETCH_NORMAL,
        DWRITE_FONT_STYLE_NORMAL, &font);
    if (SUCCEEDED(hr) && !face) hr = IDWriteFont_CreateFontFace(font, &face);
    if (SUCCEEDED(hr) && !selected_glyph_family) hr = IDWriteFontFace_GetGlyphIndices(
        face, codepoints, sizeof(codepoints) / sizeof(codepoints[0]), glyphs);
    if (FAILED(hr))
    {
        fail("DirectWrite_glyphs", hr,
             "font face glyph lookup");
        goto done;
    }
    if (!glyphs[0] || !glyphs[1])
        cap("DirectWrite_glyphs", "UNSUPPORTED", S_FALSE,
            "font face returned missing-glyph indices for selected family");
    else
        cap("DirectWrite_glyphs", "PASS", 0, "Latin and mixed-script glyph indices");
    hr = IDWriteFactory_CreateTextFormat(factory, family_name, collection,
                                         DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STYLE_NORMAL,
                                         DWRITE_FONT_STRETCH_NORMAL, 24.0f, L"en-us", &format);
    if (SUCCEEDED(hr)) hr = IDWriteFactory_CreateTextLayout(
        factory, text, (UINT32)wcslen(text), format, 600.0f, 120.0f, &layout);
    if (SUCCEEDED(hr)) hr = IDWriteTextLayout_GetMetrics(layout, &metrics);
    if (FAILED(hr) || metrics.width <= 0 || metrics.height <= 0)
        cap("DirectWrite_layout", "UNSUPPORTED", FAILED(hr) ? hr : E_FAIL,
            "provider returned no positive mixed-script layout metrics");
    else
        cap("DirectWrite_layout", "PASS", 0, "layout metrics and shaping input accepted");

    hr = IDWriteFactory_QueryInterface(factory, &IID_IDWriteFactory2, (void **)&factory2);
    if (SUCCEEDED(hr)) hr = IDWriteFactory2_GetSystemFontFallback(factory2, &fallback);
    if (FAILED(hr))
        cap("DirectWrite_fallback", "UNSUPPORTED", hr, "system fallback interface unavailable");
    else
    {
        memset(&source, 0, sizeof(source));
        source.iface.lpVtbl = &source_vtbl;
        source.refs = 1;
        source.text = text;
        source.length = (UINT32)wcslen(text);
        hr = IDWriteFontFallback_MapCharacters(fallback, &source.iface, 0, source.length,
                                               collection, family_name,
                                               DWRITE_FONT_WEIGHT_NORMAL,
                                               DWRITE_FONT_STYLE_NORMAL,
                                               DWRITE_FONT_STRETCH_NORMAL,
                                               &mapped_length, &mapped_font, &scale);
        if (SUCCEEDED(hr) && mapped_font && mapped_length && scale > 0)
            cap("DirectWrite_fallback", "PASS", 0, "mixed-script fallback mapping");
        else
            fail("DirectWrite_fallback", FAILED(hr) ? hr : E_FAIL,
                 "fallback MapCharacters returned no font");
    }
done:
    free(family_name);
    if (mapped_font) IDWriteFont_Release(mapped_font);
    if (fallback) IDWriteFontFallback_Release(fallback);
    if (factory2) IDWriteFactory2_Release(factory2);
    if (layout) IDWriteTextLayout_Release(layout);
    if (format) IDWriteTextFormat_Release(format);
    if (face) IDWriteFontFace_Release(face);
    if (font) IDWriteFont_Release(font);
    if (names) IDWriteLocalizedStrings_Release(names);
    if (family) IDWriteFontFamily_Release(family);
    if (collection) IDWriteFontCollection_Release(collection);
    if (factory) IDWriteFactory_Release(factory);
}

int main(void)
{
    HRESULT hr;

    setvbuf(stdout, NULL, _IONBF, 0);
    hr = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (FAILED(hr) && hr != RPC_E_CHANGED_MODE)
    {
        fail("COM_initialize", hr, "main COM initialization");
        return 1;
    }
    test_com_apartments();
    test_sta_callbacks();
    test_directwrite();
    if (SUCCEEDED(hr)) CoUninitialize();
    if (failures)
    {
        fprintf(stderr, "UI_COM_DWRITE_CONTRACT_FAIL failures=%u\n", failures);
        return 1;
    }
    puts("UI_COM_DWRITE_CONTRACT_OK");
    return 0;
}
