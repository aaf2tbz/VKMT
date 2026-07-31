#include <windows.h>
#include <winhttp.h>
#include <objbase.h>
#include <wincodec.h>
#include <stdio.h>
#include <atomic>
#include "WebView2.h"

static HWND window_handle;
static ICoreWebView2Controller *controller;
static ICoreWebView2 *webview;
static IStream *preview_stream;
static const wchar_t *https_url;
static bool finished;

static HRESULT prove_https(const wchar_t *url)
{
    URL_COMPONENTS parts = {};
    wchar_t host[256], path[1024];
    DWORD status = 0, status_size = sizeof(status);
    DWORD security = SECURITY_FLAG_IGNORE_CERT_CN_INVALID |
                     SECURITY_FLAG_IGNORE_CERT_DATE_INVALID |
                     SECURITY_FLAG_IGNORE_UNKNOWN_CA |
                     SECURITY_FLAG_IGNORE_CERT_WRONG_USAGE;
    HINTERNET session = nullptr, connection = nullptr, request = nullptr;
    HRESULT result = E_FAIL;

    parts.dwStructSize = sizeof(parts);
    parts.lpszHostName = host;
    parts.dwHostNameLength = ARRAYSIZE(host);
    parts.lpszUrlPath = path;
    parts.dwUrlPathLength = ARRAYSIZE(path);
    if (!WinHttpCrackUrl(url, 0, 0, &parts) ||
        parts.nScheme != INTERNET_SCHEME_HTTPS) goto done;
    session = WinHttpOpen(L"VKMT-WebView2-Probe/1.0",
                          WINHTTP_ACCESS_TYPE_NO_PROXY, nullptr, nullptr, 0);
    if (!session) goto done;
    connection = WinHttpConnect(session, host, parts.nPort, 0);
    if (!connection) goto done;
    request = WinHttpOpenRequest(connection, L"GET", path, nullptr,
                                 WINHTTP_NO_REFERER,
                                 WINHTTP_DEFAULT_ACCEPT_TYPES,
                                 WINHTTP_FLAG_SECURE);
    if (!request) goto done;
    if (!WinHttpSetOption(request, WINHTTP_OPTION_SECURITY_FLAGS,
                          &security, sizeof(security))) goto done;
    if (!WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                            WINHTTP_NO_REQUEST_DATA, 0, 0, 0) ||
        !WinHttpReceiveResponse(request, nullptr)) goto done;
    if (!WinHttpQueryHeaders(request,
                             WINHTTP_QUERY_STATUS_CODE |
                             WINHTTP_QUERY_FLAG_NUMBER,
                             WINHTTP_HEADER_NAME_BY_INDEX, &status,
                             &status_size, WINHTTP_NO_HEADER_INDEX) ||
        status != 200) goto done;
    result = S_OK;
done:
    if (request) WinHttpCloseHandle(request);
    if (connection) WinHttpCloseHandle(connection);
    if (session) WinHttpCloseHandle(session);
    return result;
}

static void fail(const char *where, HRESULT hr)
{
    printf("WEBVIEW2_FAIL %s hr=%08lx\n", where, (unsigned long)hr);
    finished = true;
    PostQuitMessage(2);
}

static const wchar_t renderer_script[] =
    L"(()=>{"
    L"const i=document.getElementById('i');"
    L"if(!i)throw new Error('fixture DOM missing');"
    L"i.value='VKMT';i.dispatchEvent(new Event('input',{bubbles:true}));"
    L"const a=new OfflineAudioContext(1,8,8000);"
    L"const b=a.createBuffer(1,8,8000);b.getChannelData(0)[0]=0.5;"
    L"return {marker:'VKMT_WEBVIEW2_OK',input:i.dataset.hit,"
    L"audio:(b.getChannelData(0)[0]===0.5?'audio-ok':'audio-bad')};"
    L"})()";

template <typename Interface, const IID *InterfaceId>
class HandlerBase : public Interface
{
    std::atomic<ULONG> refs{1};
protected:
    virtual ~HandlerBase() = default;
public:
    HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **object) override
    {
        if (!object) return E_POINTER;
        if (IsEqualIID(iid, IID_IUnknown) || IsEqualIID(iid, *InterfaceId))
        {
            *object = static_cast<Interface *>(this);
            AddRef();
            return S_OK;
        }
        *object = nullptr;
        return E_NOINTERFACE;
    }
    ULONG STDMETHODCALLTYPE AddRef() override { return ++refs; }
    ULONG STDMETHODCALLTYPE Release() override
    {
        ULONG count = --refs;
        if (!count) delete this;
        return count;
    }
};

class PreviewHandler final :
    public HandlerBase<ICoreWebView2CapturePreviewCompletedHandler,
                       &IID_ICoreWebView2CapturePreviewCompletedHandler>
{
public:
    HRESULT STDMETHODCALLTYPE Invoke(HRESULT error) override
    {
        IWICImagingFactory *factory = nullptr;
        IWICBitmapDecoder *decoder = nullptr;
        IWICBitmapFrameDecode *frame = nullptr;
        IWICFormatConverter *converter = nullptr;
        LARGE_INTEGER start = {};
        WICRect rect;
        UINT width = 0, height = 0;
        BYTE pixel[4] = {};
        HRESULT hr = error;

        if (SUCCEEDED(hr)) hr = preview_stream->Seek(start, STREAM_SEEK_SET, nullptr);
        if (SUCCEEDED(hr))
            hr = CoCreateInstance(CLSID_WICImagingFactory, nullptr,
                                  CLSCTX_INPROC_SERVER,
                                  IID_PPV_ARGS(&factory));
        if (SUCCEEDED(hr))
            hr = factory->CreateDecoderFromStream(
                preview_stream, nullptr, WICDecodeMetadataCacheOnLoad,
                &decoder);
        if (SUCCEEDED(hr)) hr = decoder->GetFrame(0, &frame);
        if (SUCCEEDED(hr)) hr = frame->GetSize(&width, &height);
        if (SUCCEEDED(hr)) hr = factory->CreateFormatConverter(&converter);
        if (SUCCEEDED(hr))
            hr = converter->Initialize(frame, GUID_WICPixelFormat32bppRGBA,
                                       WICBitmapDitherTypeNone, nullptr, 0,
                                       WICBitmapPaletteTypeCustom);
        rect = {(INT)(width / 2), (INT)(height / 2), 1, 1};
        if (SUCCEEDED(hr)) hr = converter->CopyPixels(&rect, 4, 4, pixel);

        if (converter) converter->Release();
        if (frame) frame->Release();
        if (decoder) decoder->Release();
        if (factory) factory->Release();
        preview_stream->Release();
        preview_stream = nullptr;

        if (FAILED(hr) || pixel[0] != 17 || pixel[1] != 34 ||
            pixel[2] != 51 || pixel[3] != 255)
        {
            printf("WEBVIEW2_BAD_PREVIEW size=%ux%u rgba=%u,%u,%u,%u\n",
                   width, height, pixel[0], pixel[1], pixel[2], pixel[3]);
            fail("CapturePreview pixel", FAILED(hr) ? hr : E_FAIL);
            return S_OK;
        }
        printf("WEBVIEW2_PREVIEW_PIXEL_OK size=%ux%u rgba=%u,%u,%u,%u\n",
               width, height, pixel[0], pixel[1], pixel[2], pixel[3]);
        puts("WEBVIEW2_HTTPS_INPUT_AUDIO_PIXEL_OK");
        finished = true;
        KillTimer(window_handle, 3);
        PostQuitMessage(0);
        return S_OK;
    }
};

class ScriptHandler final :
    public HandlerBase<ICoreWebView2ExecuteScriptCompletedHandler,
                       &IID_ICoreWebView2ExecuteScriptCompletedHandler>
{
public:
    HRESULT STDMETHODCALLTYPE Invoke(HRESULT error, LPCWSTR result) override
    {
        if (FAILED(error) || !result)
        {
            fail("ExecuteScript callback", error);
            return S_OK;
        }
        bool marker = wcsstr(result, L"VKMT_WEBVIEW2_OK") != nullptr;
        bool input = wcsstr(result, L"input-ok") != nullptr;
        bool audio = wcsstr(result, L"audio-ok") != nullptr;
        if (!marker || !input || !audio)
        {
            wprintf(L"WEBVIEW2_BAD_RESULT %ls\n", result);
            fail("deterministic result", E_FAIL);
            return S_OK;
        }
        wprintf(L"WEBVIEW2_SCRIPT_RESULT %ls\n", result);
        HRESULT hr = CreateStreamOnHGlobal(nullptr, TRUE, &preview_stream);
        if (FAILED(hr))
        {
            fail("CreateStreamOnHGlobal", hr);
            return S_OK;
        }
        auto handler = new PreviewHandler();
        hr = webview->CapturePreview(COREWEBVIEW2_CAPTURE_PREVIEW_IMAGE_FORMAT_PNG,
                                     preview_stream, handler);
        handler->Release();
        if (FAILED(hr)) fail("CapturePreview", hr);
        else puts("WEBVIEW2_CAPTURE_PREVIEW_STARTED");
        return S_OK;
    }
};

class NavigationHandler final :
    public HandlerBase<ICoreWebView2NavigationCompletedEventHandler,
                       &IID_ICoreWebView2NavigationCompletedEventHandler>
{
public:
    HRESULT STDMETHODCALLTYPE Invoke(
        ICoreWebView2 *, ICoreWebView2NavigationCompletedEventArgs *args) override
    {
        puts("WEBVIEW2_NAVIGATION_COMPLETED");
        BOOL success = FALSE;
        HRESULT hr = args->get_IsSuccess(&success);
        if (FAILED(hr) || !success)
        {
            COREWEBVIEW2_WEB_ERROR_STATUS status;
            args->get_WebErrorStatus(&status);
            printf("WEBVIEW2_NAV_FAIL status=%d\n", (int)status);
            fail("navigation", FAILED(hr) ? hr : E_FAIL);
            return S_OK;
        }
        auto handler = new ScriptHandler();
        hr = webview->ExecuteScript(renderer_script, handler);
        handler->Release();
        if (FAILED(hr)) fail("ExecuteScript", hr);
        else
        {
            puts("WEBVIEW2_RENDERER_SCRIPT_STARTED");
            SetTimer(window_handle, 3, 30000, nullptr);
        }
        return S_OK;
    }
};

class ControllerHandler final :
    public HandlerBase<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler,
                       &IID_ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>
{
public:
    HRESULT STDMETHODCALLTYPE Invoke(
        HRESULT error, ICoreWebView2Controller *result) override
    {
        if (FAILED(error) || !result)
        {
            fail("CreateCoreWebView2Controller", error);
            return S_OK;
        }
        controller = result;
        controller->AddRef();
        puts("WEBVIEW2_CONTROLLER_OK");
        RECT bounds = {0, 0, 640, 480};
        controller->put_Bounds(bounds);
        controller->put_IsVisible(TRUE);
        HRESULT hr = controller->get_CoreWebView2(&webview);
        if (FAILED(hr)) { fail("get_CoreWebView2", hr); return S_OK; }
        EventRegistrationToken navigation_token;
        auto navigation_handler = new NavigationHandler();
        hr = webview->add_NavigationCompleted(navigation_handler,
                                              &navigation_token);
        navigation_handler->Release();
        if (FAILED(hr))
        {
            fail("add_NavigationCompleted", hr);
            return S_OK;
        }
        hr = prove_https(https_url);
        if (FAILED(hr)) { fail("host HTTPS transport", hr); return S_OK; }
        puts("WEBVIEW2_HTTPS_TRANSPORT_OK");
        hr = webview->NavigateToString(
            L"<!doctype html><body style='margin:0;background:#112233;"
            L"width:100vw;height:100vh;overflow:hidden'><input id=i>"
            L"<script>"
            L"i.addEventListener('input',()=>i.dataset.hit='input-ok');"
            L"</script>");
        if (FAILED(hr)) fail("NavigateToString", hr);
        else
            puts("WEBVIEW2_RENDERER_NAVIGATION_STARTED");
        return S_OK;
    }
};

class EnvironmentHandler final :
    public HandlerBase<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler,
                       &IID_ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>
{
public:
    HRESULT STDMETHODCALLTYPE Invoke(
        HRESULT error, ICoreWebView2Environment *environment) override
    {
        if (FAILED(error) || !environment)
        {
            fail("CreateCoreWebView2Environment", error);
            return S_OK;
        }
        puts("WEBVIEW2_ENVIRONMENT_OK");
        auto handler = new ControllerHandler();
        HRESULT hr = environment->CreateCoreWebView2Controller(window_handle, handler);
        handler->Release();
        if (FAILED(hr)) fail("CreateCoreWebView2Controller call", hr);
        return S_OK;
    }
};

static LRESULT CALLBACK window_proc(HWND hwnd, UINT message, WPARAM wparam,
                                    LPARAM lparam)
{
    if (message == WM_SIZE && controller)
    {
        RECT bounds;
        GetClientRect(hwnd, &bounds);
        controller->put_Bounds(bounds);
    }
    if (message == WM_TIMER && wparam == 1 && !finished)
    {
        fail("timeout", HRESULT_FROM_WIN32(ERROR_TIMEOUT));
        return 0;
    }
    if (message == WM_TIMER && wparam == 3 && !finished)
    {
        KillTimer(hwnd, 3);
        fail("ExecuteScript callback timeout",
             HRESULT_FROM_WIN32(ERROR_TIMEOUT));
        return 0;
    }
    return DefWindowProcW(hwnd, message, wparam, lparam);
}

int wmain(int argc, wchar_t **argv)
{
    setvbuf(stdout, nullptr, _IONBF, 0);
    setvbuf(stderr, nullptr, _IONBF, 0);
    if (argc != 4)
    {
        fputs("usage: webview2_fixed_probe.exe RUNTIME USER_DATA HTTPS_URL\n", stderr);
        return 64;
    }
    https_url = argv[3];
    HRESULT hr = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    if (FAILED(hr)) { fail("CoInitializeEx", hr); return 2; }
    HINSTANCE instance = GetModuleHandleW(nullptr);
    WNDCLASSW cls = {};
    cls.lpfnWndProc = window_proc;
    cls.hInstance = instance;
    cls.lpszClassName = L"VKMTWebView2Probe";
    if (!RegisterClassW(&cls)) return 3;
    window_handle = CreateWindowW(cls.lpszClassName, L"VKMT WebView2 Probe",
                                  WS_OVERLAPPEDWINDOW, CW_USEDEFAULT,
                                  CW_USEDEFAULT, 640, 480, nullptr, nullptr,
                                  instance, nullptr);
    if (!window_handle) return 4;
    ShowWindow(window_handle, SW_SHOW);
    SetTimer(window_handle, 1, 90000, nullptr);

    HMODULE loader = LoadLibraryW(L"WebView2Loader.dll");
    if (!loader) return 5;
    using CreateEnvironment = HRESULT (STDAPICALLTYPE *)(
        PCWSTR, PCWSTR, ICoreWebView2EnvironmentOptions *,
        ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler *);
    auto create_environment = reinterpret_cast<CreateEnvironment>(
        GetProcAddress(loader, "CreateCoreWebView2EnvironmentWithOptions"));
    if (!create_environment) return 6;
    auto handler = new EnvironmentHandler();
    hr = create_environment(argv[1], argv[2], nullptr, handler);
    handler->Release();
    if (FAILED(hr)) { fail("CreateCoreWebView2Environment call", hr); }

    MSG message;
    while (GetMessageW(&message, nullptr, 0, 0) > 0)
    {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    if (webview) webview->Release();
    if (controller) { controller->Close(); controller->Release(); }
    FreeLibrary(loader);
    CoUninitialize();
    return finished ? (int)message.wParam : 2;
}
