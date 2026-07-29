#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <ole2.h>
#include <servprov.h>
#include <initguid.h>
#include <mshtml.h>
#include <stdio.h>
#include <wchar.h>

static IOleClientSite client_site;
static IServiceProvider service_provider;

static HRESULT WINAPI host_QueryInterface(IOleClientSite *iface, REFIID riid, void **out)
{
    if (!out) return E_POINTER;
    *out = NULL;
    if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &IID_IOleClientSite))
        *out = &client_site;
    else if (IsEqualIID(riid, &IID_IServiceProvider))
        *out = &service_provider;
    if (!*out) return E_NOINTERFACE;
    IUnknown_AddRef((IUnknown *)*out);
    return S_OK;
}

static ULONG WINAPI host_AddRef(IOleClientSite *iface)
{
    return 2;
}

static ULONG WINAPI host_Release(IOleClientSite *iface)
{
    return 1;
}

static HRESULT WINAPI host_SaveObject(IOleClientSite *iface)
{
    return E_NOTIMPL;
}

static HRESULT WINAPI host_GetMoniker(IOleClientSite *iface, DWORD assign, DWORD which,
                                      IMoniker **moniker)
{
    if (moniker) *moniker = NULL;
    return E_NOTIMPL;
}

static HRESULT WINAPI host_GetContainer(IOleClientSite *iface, IOleContainer **container)
{
    if (container) *container = NULL;
    return E_NOINTERFACE;
}

static HRESULT WINAPI host_ShowObject(IOleClientSite *iface)
{
    return S_OK;
}

static HRESULT WINAPI host_OnShowWindow(IOleClientSite *iface, BOOL show)
{
    return S_OK;
}

static HRESULT WINAPI host_RequestNewObjectLayout(IOleClientSite *iface)
{
    return E_NOTIMPL;
}

static const IOleClientSiteVtbl client_site_vtbl = {
    host_QueryInterface,
    host_AddRef,
    host_Release,
    host_SaveObject,
    host_GetMoniker,
    host_GetContainer,
    host_ShowObject,
    host_OnShowWindow,
    host_RequestNewObjectLayout
};

static HRESULT WINAPI services_QueryInterface(IServiceProvider *iface, REFIID riid, void **out)
{
    return host_QueryInterface(&client_site, riid, out);
}

static ULONG WINAPI services_AddRef(IServiceProvider *iface)
{
    return 2;
}

static ULONG WINAPI services_Release(IServiceProvider *iface)
{
    return 1;
}

static HRESULT WINAPI services_QueryService(IServiceProvider *iface, REFGUID service,
                                             REFIID riid, void **out)
{
    if (out) *out = NULL;
    return E_NOINTERFACE;
}

static const IServiceProviderVtbl service_provider_vtbl = {
    services_QueryInterface,
    services_AddRef,
    services_Release,
    services_QueryService
};

static IOleClientSite client_site = { &client_site_vtbl };
static IServiceProvider service_provider = { &service_provider_vtbl };

static void pump_messages(void)
{
    MSG msg;
    while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE))
    {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
}

static void stage(const char *name)
{
    puts(name);
    fflush(stdout);
}

static int wait_ready(IHTMLDocument2 *doc, DWORD timeout, BOOL accept_interactive)
{
    DWORD start = GetTickCount();
    WCHAR last_state[64] = L"";
    HRESULT last_hr = E_FAIL;

    while (GetTickCount() - start < timeout)
    {
        BSTR state = NULL;
        pump_messages();
        last_hr = IHTMLDocument2_get_readyState(doc, &state);
        if (SUCCEEDED(last_hr) && state)
        {
            int ready = !wcscmp(state, L"complete") ||
                        (accept_interactive && !wcscmp(state, L"interactive"));
            if (wcscmp(last_state, state))
            {
                wprintf(L"MSHTML_READY_STATE=%ls\n", state);
                fflush(stdout);
                wcsncpy(last_state, state, sizeof(last_state) / sizeof(last_state[0]) - 1);
                last_state[sizeof(last_state) / sizeof(last_state[0]) - 1] = 0;
            }
            SysFreeString(state);
            if (ready) return 1;
        }
        else if (FAILED(last_hr))
        {
            fprintf(stderr, "get_readyState failed: %08lx\n", last_hr);
            return 0;
        }
        Sleep(10);
    }
    fwprintf(stderr, L"readyState timeout after %lu ms (state=%ls hr=%08lx)\n",
             timeout, last_state[0] ? last_state : L"(null)", last_hr);
    return 0;
}

static int expect_title(IHTMLDocument2 *doc, const WCHAR *expected)
{
    BSTR title = NULL;
    HRESULT hr = IHTMLDocument2_get_title(doc, &title);
    int ok = SUCCEEDED(hr) && title && !wcscmp(title, expected);
    if (!ok) fwprintf(stderr, L"title mismatch: %ls\n", title ? title : L"(null)");
    SysFreeString(title);
    return ok;
}

static int wait_title(IHTMLDocument2 *doc, const WCHAR *expected, DWORD timeout)
{
    DWORD start = GetTickCount();

    while (GetTickCount() - start < timeout)
    {
        BSTR title = NULL;
        HRESULT hr;

        pump_messages();
        hr = IHTMLDocument2_get_title(doc, &title);
        if (SUCCEEDED(hr) && title && !wcscmp(title, expected))
        {
            SysFreeString(title);
            return 1;
        }
        SysFreeString(title);
        if (FAILED(hr))
        {
            fprintf(stderr, "get_title failed while waiting: %08lx\n", hr);
            return 0;
        }
        Sleep(10);
    }
    return expect_title(doc, expected);
}

int wmain(void)
{
    static const WCHAR html[] =
        L"<html><head><title>initial</title>"
        L"<script>document.title='VKMT_JS_OK';</script></head>"
        L"<body><div id='probe' onclick=\"document.title='VKMT_EVENT_OK'\">go</div>"
        L"<div id='dom'>VKMT_DOM_OK</div></body></html>";
    IHTMLDocument2 *doc = NULL;
    IHTMLDocument3 *doc3 = NULL;
    IPersistStreamInit *persist = NULL;
    IOleObject *ole_object = NULL;
    IHTMLElement3 *button3 = NULL;
    IHTMLElement *button = NULL, *dom = NULL;
    HMODULE mshtml_module = NULL;
    SAFEARRAY *array = NULL;
    VARIANT *item;
    BSTR id = NULL, text = NULL, url = NULL;
    HRESULT hr;
    int ret = 1;

    hr = CoInitialize(NULL);
    if (FAILED(hr)) return 2;
    mshtml_module = LoadLibraryW(L"mshtml.dll");
    if (!mshtml_module)
    {
        fprintf(stderr, "LoadLibrary(mshtml.dll) failed: %lu\n", GetLastError());
        goto done;
    }
    {
        typedef HRESULT (WINAPI *dll_get_class_object_fn)(REFCLSID, REFIID, void **);
        dll_get_class_object_fn get_class_object;
        IClassFactory *factory = NULL;

        get_class_object = (dll_get_class_object_fn)GetProcAddress(mshtml_module, "DllGetClassObject");
        if (!get_class_object)
        {
            fprintf(stderr, "GetProcAddress(DllGetClassObject) failed: %lu\n", GetLastError());
            goto done;
        }
        hr = get_class_object(&CLSID_HTMLDocument, &IID_IClassFactory, (void **)&factory);
        printf("MSHTML_DLL_GET_CLASS_OBJECT=%08lx\n", hr);
        fflush(stdout);
        if (factory) IClassFactory_Release(factory);
        if (FAILED(hr)) goto done;
    }
    {
        WCHAR module_path[MAX_PATH];
        if (!GetModuleFileNameW(mshtml_module, module_path, MAX_PATH))
        {
            fprintf(stderr, "GetModuleFileName(mshtml.dll) failed: %lu\n", GetLastError());
            goto done;
        }
        wprintf(L"MSHTML_MODULE=%ls\n", module_path);
        fflush(stdout);
    }
    stage("MSHTML_CLASS_EXPORT_OK");
    hr = CoCreateInstance(&CLSID_HTMLDocument, NULL,
                          CLSCTX_INPROC_SERVER | CLSCTX_INPROC_HANDLER,
                          &IID_IHTMLDocument2, (void **)&doc);
    if (FAILED(hr))
    {
        fprintf(stderr, "CoCreateInstance failed: %08lx\n", hr);
        goto done;
    }
    stage("MSHTML_DOCUMENT_CREATED");
    hr = IHTMLDocument2_QueryInterface(doc, &IID_IOleObject, (void **)&ole_object);
    if (FAILED(hr) || FAILED(IOleObject_SetClientSite(ole_object, &client_site)))
    {
        fprintf(stderr, "MSHTML client-site setup failed: %08lx\n", hr);
        goto done;
    }
    stage("MSHTML_CLIENT_SITE_OK");
    hr = IHTMLDocument2_QueryInterface(doc, &IID_IPersistStreamInit, (void **)&persist);
    if (FAILED(hr))
    {
        fprintf(stderr, "IPersistStreamInit QI failed: %08lx\n", hr);
        goto done;
    }
    stage("MSHTML_PERSIST_ACQUIRED");
    hr = IPersistStreamInit_InitNew(persist);
    if (FAILED(hr))
    {
        fprintf(stderr, "IPersistStreamInit::InitNew failed: %08lx\n", hr);
        goto done;
    }
    stage("MSHTML_INITNEW_OK");

    array = SafeArrayCreateVector(VT_VARIANT, 0, 1);
    if (!array || FAILED(SafeArrayAccessData(array, (void **)&item))) goto done;
    VariantInit(item);
    V_VT(item) = VT_BSTR;
    V_BSTR(item) = SysAllocString(html);
    SafeArrayUnaccessData(array);
    hr = IHTMLDocument2_write(doc, array);
    SafeArrayDestroy(array);
    array = NULL;
    if (FAILED(hr))
    {
        fprintf(stderr, "IHTMLDocument2::write failed: %08lx\n", hr);
        goto done;
    }
    stage("MSHTML_WRITE_OK");
    hr = IHTMLDocument2_close(doc);
    if (FAILED(hr))
    {
        fprintf(stderr, "IHTMLDocument2::close failed: %08lx\n", hr);
        goto done;
    }
    stage("MSHTML_CLOSE_OK");
    /*
     * A stream-initialized, unhosted MSHTML document may remain interactive
     * after close even though parsing and synchronous scripts are complete.
     * The following JavaScript and DOM assertions are the substantive gates.
     * Network navigation below still requires the real complete state.
     */
    if (!wait_ready(doc, 15000, TRUE)) goto done;
    stage("MSHTML_DOCUMENT_READY");
    if (!expect_title(doc, L"VKMT_JS_OK")) goto done;
    stage("MSHTML_JAVASCRIPT_OK");

    if (FAILED(IHTMLDocument2_QueryInterface(doc, &IID_IHTMLDocument3, (void **)&doc3))) goto done;
    id = SysAllocString(L"dom");
    if (FAILED(IHTMLDocument3_getElementById(doc3, id, &dom))) goto done;
    SysFreeString(id);
    id = NULL;
    if (!dom || FAILED(IHTMLElement_get_innerText(dom, &text)) ||
        !text || wcscmp(text, L"VKMT_DOM_OK")) goto done;
    SysFreeString(text);
    text = NULL;
    stage("MSHTML_DOM_OK");

    id = SysAllocString(L"probe");
    if (FAILED(IHTMLDocument3_getElementById(doc3, id, &button))) goto done;
    SysFreeString(id);
    id = NULL;
    if (!button || FAILED(IHTMLElement_QueryInterface(button, &IID_IHTMLElement3, (void **)&button3)))
        goto done;
    {
        VARIANT event_object;
        VARIANT_BOOL not_cancelled = VARIANT_FALSE;
        BSTR event_name = SysAllocString(L"onclick");

        VariantInit(&event_object);
        hr = IHTMLElement3_fireEvent(button3, event_name, &event_object, &not_cancelled);
        SysFreeString(event_name);
        if (FAILED(hr) || not_cancelled != VARIANT_TRUE)
        {
            fprintf(stderr, "IHTMLElement3::fireEvent failed: %08lx result=%x\n",
                    hr, not_cancelled);
            goto done;
        }
    }
    if (!wait_title(doc, L"VKMT_EVENT_OK", 5000)) goto done;
    stage("MSHTML_EVENT_OK");

    {
        IHTMLWindow2 *window = NULL;
        IHTMLLocation *location = NULL;
        BSTR target = SysAllocString(L"https://example.com/");
        if (FAILED(IHTMLDocument2_get_parentWindow(doc, &window)) || !window ||
            FAILED(IHTMLWindow2_get_location(window, &location)) || !location ||
            FAILED(IHTMLLocation_put_href(location, target)))
        {
            SysFreeString(target);
            if (location) IHTMLLocation_Release(location);
            if (window) IHTMLWindow2_Release(window);
            goto done;
        }
        SysFreeString(target);
        IHTMLLocation_Release(location);
        IHTMLWindow2_Release(window);
    }
    if (!wait_ready(doc, 30000, FALSE) || FAILED(IHTMLDocument2_get_URL(doc, &url)) ||
        !url || wcsncmp(url, L"https://example.com", 19)) goto done;
    stage("MSHTML_HTTPS_NAVIGATION_OK");
    ret = 0;

done:
    if (url) SysFreeString(url);
    if (text) SysFreeString(text);
    if (id) SysFreeString(id);
    if (array) SafeArrayDestroy(array);
    if (button3) IHTMLElement3_Release(button3);
    if (button) IHTMLElement_Release(button);
    if (dom) IHTMLElement_Release(dom);
    if (doc3) IHTMLDocument3_Release(doc3);
    if (persist) IPersistStreamInit_Release(persist);
    if (ole_object)
    {
        IOleObject_SetClientSite(ole_object, NULL);
        IOleObject_Release(ole_object);
    }
    if (doc) IHTMLDocument2_Release(doc);
    if (mshtml_module) FreeLibrary(mshtml_module);
    CoUninitialize();
    if (!ret) stage("MSHTML_RUNTIME_ALL_OK");
    return ret;
}
