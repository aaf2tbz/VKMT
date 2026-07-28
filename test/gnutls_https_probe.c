#define SECURITY_WIN32
#include <windows.h>
#include <security.h>
#include <schannel.h>
#include <winhttp.h>
#include <stdio.h>
#include <string.h>

#define VKMT_INTERNET_OPEN_TYPE_DIRECT 1
#define VKMT_INTERNET_FLAG_RELOAD 0x80000000
#define VKMT_INTERNET_FLAG_NO_CACHE_WRITE 0x04000000
#define VKMT_INTERNET_FLAG_SECURE 0x00800000
#define VKMT_HTTP_QUERY_STATUS_CODE 19
#define VKMT_HTTP_QUERY_FLAG_NUMBER 0x20000000

typedef HINTERNET (WINAPI *PFNINTERNETOPENA)(LPCSTR, DWORD, LPCSTR, LPCSTR, DWORD);
typedef HINTERNET (WINAPI *PFNINTERNETOPENURLA)(HINTERNET, LPCSTR, LPCSTR, DWORD, DWORD, DWORD_PTR);
typedef BOOL (WINAPI *PFNHTTPQUERYINFOA)(HINTERNET, DWORD, LPVOID, LPDWORD, LPDWORD);
typedef BOOL (WINAPI *PFNINTERNETCLOSEHANDLE)(HINTERNET);

static int probe_schannel(void)
{
    SCHANNEL_CRED credentials = {0};
    CredHandle handle;
    TimeStamp expiry;
    SECURITY_STATUS status;

    credentials.dwVersion = SCHANNEL_CRED_VERSION;
    status = AcquireCredentialsHandleA(NULL, UNISP_NAME_A, SECPKG_CRED_OUTBOUND,
                                       NULL, &credentials, NULL, NULL, &handle, &expiry);
    if (status != SEC_E_OK)
    {
        printf("FAIL Schannel credentials status=0x%lx\n", (unsigned long)status);
        return 0;
    }
    FreeCredentialsHandle(&handle);
    puts("GNUTLS_SCHANNEL_CREDENTIALS_OK");
    return 1;
}

static int probe_winhttp(void)
{
    HINTERNET session, connection, request;
    DWORD status = 0, size = sizeof(status);
    int ok = 0;

    session = WinHttpOpen(L"VKMT-GnuTLS/1.0", WINHTTP_ACCESS_TYPE_NO_PROXY,
                          WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, 0);
    if (!session) return 0;
    WinHttpSetTimeouts(session, 10000, 10000, 15000, 15000);
    connection = WinHttpConnect(session, L"example.com", INTERNET_DEFAULT_HTTPS_PORT, 0);
    if (!connection) goto done_session;
    request = WinHttpOpenRequest(connection, L"GET", L"/", NULL, WINHTTP_NO_REFERER,
                                 WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
    if (!request) goto done_connection;
    if (WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                           WINHTTP_NO_REQUEST_DATA, 0, 0, 0) &&
        WinHttpReceiveResponse(request, NULL) &&
        WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                            NULL, &status, &size, NULL) && status == 200)
        ok = 1;
    else
        printf("FAIL WinHTTP HTTPS error=%lu status=%lu\n", GetLastError(), status);
    WinHttpCloseHandle(request);
done_connection:
    WinHttpCloseHandle(connection);
done_session:
    WinHttpCloseHandle(session);
    if (ok) puts("GNUTLS_WINHTTP_HTTPS_OK");
    return ok;
}

static int probe_wininet(void)
{
    HMODULE module;
    PFNINTERNETOPENA internet_open;
    PFNINTERNETOPENURLA internet_open_url;
    PFNHTTPQUERYINFOA query_info;
    PFNINTERNETCLOSEHANDLE close_handle;
    HINTERNET internet, url;
    DWORD status = 0, size = sizeof(status);
    int ok = 0;

    module = LoadLibraryA("wininet.dll");
    if (!module) return 0;
    internet_open = (PFNINTERNETOPENA)GetProcAddress(module, "InternetOpenA");
    internet_open_url = (PFNINTERNETOPENURLA)GetProcAddress(module, "InternetOpenUrlA");
    query_info = (PFNHTTPQUERYINFOA)GetProcAddress(module, "HttpQueryInfoA");
    close_handle = (PFNINTERNETCLOSEHANDLE)GetProcAddress(module, "InternetCloseHandle");
    if (!internet_open || !internet_open_url || !query_info || !close_handle) return 0;
    internet = internet_open("VKMT-GnuTLS/1.0", VKMT_INTERNET_OPEN_TYPE_DIRECT, NULL, NULL, 0);
    if (!internet) return 0;
    url = internet_open_url(internet, "https://example.com/", NULL, 0,
                            VKMT_INTERNET_FLAG_NO_CACHE_WRITE | VKMT_INTERNET_FLAG_RELOAD |
                            VKMT_INTERNET_FLAG_SECURE, 0);
    if (url && query_info(url, VKMT_HTTP_QUERY_STATUS_CODE | VKMT_HTTP_QUERY_FLAG_NUMBER,
                          &status, &size, NULL) && status == 200)
        ok = 1;
    else
        printf("FAIL WinINet HTTPS error=%lu status=%lu\n", GetLastError(), status);
    if (url) close_handle(url);
    close_handle(internet);
    FreeLibrary(module);
    if (ok) puts("GNUTLS_WININET_HTTPS_OK");
    return ok;
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    if (!probe_schannel()) return 1;
    if (argc > 1 && !strcmp(argv[1], "--schannel-only"))
    {
        puts("GNUTLS_SCHANNEL_ONLY_OK");
        return 0;
    }
    puts("GNUTLS_WINHTTP_BEGIN");
    if (!probe_winhttp()) return 1;
    if (argc > 1 && !strcmp(argv[1], "--winhttp-only")) return 0;
    puts("GNUTLS_WININET_BEGIN");
    if (!probe_wininet()) return 1;
    puts("GNUTLS_HTTPS_ALL_OK");
    return 0;
}
