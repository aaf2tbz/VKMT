/* Deterministic local TLS trust contract for WinHTTP and WinINet.  The
 * runner supplies a localhost server and a root DER file; no certificate
 * bypass flags are used. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wincrypt.h>
#include <winhttp.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

static unsigned int failures;
static unsigned short proxy_port;

/* winhttp.h and wininet.h export overlapping types that cannot be included
 * together with this MinGW SDK.  Keep WinINet late-bound, as the production
 * runtime does, and define only the small contract surface used here. */
#define VKMT_INTERNET_OPEN_TYPE_DIRECT 1
#define VKMT_INTERNET_OPEN_TYPE_PROXY 3
#define VKMT_INTERNET_FLAG_RELOAD 0x80000000
#define VKMT_INTERNET_FLAG_NO_CACHE_WRITE 0x04000000
#define VKMT_INTERNET_FLAG_SECURE 0x00800000
#define VKMT_HTTP_QUERY_STATUS_CODE 19
#define VKMT_HTTP_QUERY_FLAG_NUMBER 0x20000000
typedef HINTERNET (WINAPI *PFNINTERNETOPENW)(LPCWSTR, DWORD, LPCWSTR, LPCWSTR, DWORD);
typedef HINTERNET (WINAPI *PFNINTERNETOPENURLW)(HINTERNET, LPCWSTR, LPCWSTR, DWORD, DWORD, DWORD_PTR);
typedef BOOL (WINAPI *PFNHTTPQUERYINFOW)(HINTERNET, DWORD, LPVOID, LPDWORD, LPDWORD);
typedef BOOL (WINAPI *PFNINTERNETCLOSEHANDLE)(HINTERNET);

static void cap(const char *api, const char *status, DWORD error, const char *detail)
{
    printf("TLS_CAP\t%s\t%s\t%s\t%lu\t%s\n", VKMT_ARCH, api, status,
           (unsigned long)error, detail ? detail : "-");
}

static void fail(const char *api, DWORD error, const char *detail)
{
    ++failures;
    cap(api, "FAIL", error, detail);
}

static unsigned char *read_file(const char *path, DWORD *size)
{
    HANDLE file;
    LARGE_INTEGER length;
    unsigned char *data;
    DWORD read;

    file = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING,
                       FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE || !GetFileSizeEx(file, &length) ||
        length.QuadPart <= 0 || length.QuadPart > 1024 * 1024)
    {
        if (file != INVALID_HANDLE_VALUE) CloseHandle(file);
        return NULL;
    }
    *size = (DWORD)length.QuadPart;
    data = malloc(*size);
    if (!data || !ReadFile(file, data, *size, &read, NULL) || read != *size)
    {
        free(data);
        data = NULL;
    }
    CloseHandle(file);
    return data;
}

static PCCERT_CONTEXT install_root(const char *path, const char *crl_path, HCERTSTORE *store)
{
    unsigned char *encoded;
    unsigned char *crl_encoded;
    DWORD size;
    DWORD crl_size;
    PCCERT_CONTEXT root = NULL;
    HCERTSTORE system_store;

    encoded = read_file(path, &size);
    if (!encoded)
    {
        fail("certificate_root", GetLastError(), "read DER root");
        return NULL;
    }
    system_store = CertOpenStore(CERT_STORE_PROV_SYSTEM_W,
                                 X509_ASN_ENCODING | PKCS_7_ASN_ENCODING, 0,
                                 CERT_SYSTEM_STORE_CURRENT_USER | CERT_STORE_MAXIMUM_ALLOWED_FLAG,
                                 L"ROOT");
    if (!system_store || !CertAddEncodedCertificateToStore(
            system_store, X509_ASN_ENCODING | PKCS_7_ASN_ENCODING, encoded, size,
            CERT_STORE_ADD_REPLACE_EXISTING, &root))
    {
        fail("certificate_root", GetLastError(), "install current-user root");
        if (system_store) CertCloseStore(system_store, 0);
        free(encoded);
        return NULL;
    }
    free(encoded);
    crl_encoded = strcmp(crl_path, "-") ? read_file(crl_path, &crl_size) : NULL;
    if (strcmp(crl_path, "-") && (!crl_encoded || !CertAddEncodedCRLToStore(
            system_store, X509_ASN_ENCODING | PKCS_7_ASN_ENCODING,
            crl_encoded, crl_size, CERT_STORE_ADD_REPLACE_EXISTING, NULL)))
    {
        fail("certificate_crl", GetLastError(), "install current-user intermediate CRL");
        free(crl_encoded);
        CertDeleteCertificateFromStore(root);
        CertCloseStore(system_store, 0);
        return NULL;
    }
    free(crl_encoded);
    if (!CertControlStore(system_store, 0, CERT_STORE_CTRL_COMMIT, NULL))
    {
        fail("certificate_root", GetLastError(), "commit current-user trust store");
        CertDeleteCertificateFromStore(root);
        CertCloseStore(system_store, 0);
        return NULL;
    }
    {
        PCCERT_CONTEXT duplicate = CertDuplicateCertificateContext(root);
        HCERTSTORE reopened;
        CertFreeCertificateContext(root);
        root = NULL;
        CertCloseStore(system_store, 0);
        reopened = CertOpenStore(CERT_STORE_PROV_SYSTEM_W,
                                 X509_ASN_ENCODING | PKCS_7_ASN_ENCODING, 0,
                                 CERT_SYSTEM_STORE_CURRENT_USER | CERT_STORE_MAXIMUM_ALLOWED_FLAG,
                                 L"ROOT");
        if (!duplicate || !reopened || !(root = CertFindCertificateInStore(
                reopened, X509_ASN_ENCODING | PKCS_7_ASN_ENCODING, 0,
                CERT_FIND_EXISTING, duplicate, NULL)))
        {
            fail("certificate_root", GetLastError(), "reopen current-user trust store");
            if (duplicate) CertFreeCertificateContext(duplicate);
            if (reopened) CertCloseStore(reopened, 0);
            return NULL;
        }
        CertFreeCertificateContext(duplicate);
        system_store = reopened;
    }
    if (!CertControlStore(system_store, 0, CERT_STORE_CTRL_RESYNC, NULL))
    {
        fail("certificate_root", GetLastError(), "resync current-user trust store");
        CertDeleteCertificateFromStore(root);
        CertCloseStore(system_store, 0);
        return NULL;
    }
    {
        CERT_CHAIN_PARA chain_parameters = {0};
        PCCERT_CHAIN_CONTEXT chain = NULL;
        chain_parameters.cbSize = sizeof(chain_parameters);
        if (!CertGetCertificateChain(NULL, root, NULL, system_store,
                                     &chain_parameters, 0, NULL, &chain))
        {
            fail("certificate_chain_seed", GetLastError(), "seed current-user chain engine");
            CertDeleteCertificateFromStore(root);
            CertCloseStore(system_store, 0);
            return NULL;
        }
        cap("certificate_chain_seed", "PASS", chain->TrustStatus.dwErrorStatus,
            "current-user root visible to chain engine");
        CertFreeCertificateChain(chain);
    }
    if (strcmp(crl_path, "-"))
        cap("certificate_crl", "PASS", 0, "installed current-user intermediate CRL");
    *store = system_store;
    cap("certificate_root", "PASS", 0, "installed current-user localhost root");
    return root;
}

static int winhttp_request(unsigned short port, int expected_valid)
{
    HINTERNET session = NULL, connection = NULL, request = NULL;
    WCHAR proxy[64];
    DWORD access_type = WINHTTP_ACCESS_TYPE_NO_PROXY;
    LPCWSTR proxy_name = WINHTTP_NO_PROXY_NAME;
    DWORD status = 0, size = sizeof(status), error = 0;
    int ok = 0;

    if (proxy_port)
    {
        swprintf(proxy, sizeof(proxy) / sizeof(proxy[0]), L"127.0.0.1:%u", proxy_port);
        access_type = WINHTTP_ACCESS_TYPE_NAMED_PROXY;
        proxy_name = proxy;
    }
    session = WinHttpOpen(L"VKMT-TLS-Contract/1.0", access_type,
                          proxy_name, WINHTTP_NO_PROXY_BYPASS, 0);
    if (session) WinHttpSetTimeouts(session, 5000, 5000, 5000, 5000);
    connection = session ? WinHttpConnect(session, L"localhost", port, 0) : NULL;
    request = connection ? WinHttpOpenRequest(connection, L"GET", L"/", NULL,
                                               WINHTTP_NO_REFERER,
                                               WINHTTP_DEFAULT_ACCEPT_TYPES,
                                               WINHTTP_FLAG_SECURE) : NULL;
    if (request && WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0,
                                      WINHTTP_NO_REQUEST_DATA, 0, 0, 0) &&
        WinHttpReceiveResponse(request, NULL) &&
        WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                            NULL, &status, &size, NULL))
        ok = status == 200;
    error = GetLastError();
    if (expected_valid)
    {
        if (ok) cap("WinHTTP", "PASS", 0, proxy_port ?
            "trusted localhost chain via fragmented CONNECT proxy" :
            "trusted localhost chain and hostname");
        else fail("WinHTTP", error, "valid chain rejected");
    }
    else if (!ok)
        cap("WinHTTP", "PASS", error, "invalid certificate rejected");
    else
        fail("WinHTTP", 0, "invalid certificate accepted");
    if (request) WinHttpCloseHandle(request);
    if (connection) WinHttpCloseHandle(connection);
    if (session) WinHttpCloseHandle(session);
    return ok == expected_valid;
}

static int wininet_request(unsigned short port, int expected_valid)
{
    HMODULE module = NULL;
    PFNINTERNETOPENW internet_open;
    PFNINTERNETOPENURLW internet_open_url;
    PFNHTTPQUERYINFOW query_info;
    PFNINTERNETCLOSEHANDLE close_handle;
    HINTERNET internet = NULL, url = NULL;
    WCHAR address[128];
    WCHAR proxy[64];
    DWORD access_type = VKMT_INTERNET_OPEN_TYPE_DIRECT;
    LPCWSTR proxy_name = NULL;
    DWORD status = 0, size = sizeof(status), error = 0;
    int ok = 0;

    swprintf(address, sizeof(address) / sizeof(address[0]),
             L"https://localhost:%u/", port);
    module = LoadLibraryA("wininet.dll");
    internet_open = module ? (PFNINTERNETOPENW)GetProcAddress(module, "InternetOpenW") : NULL;
    internet_open_url = module ? (PFNINTERNETOPENURLW)GetProcAddress(module, "InternetOpenUrlW") : NULL;
    query_info = module ? (PFNHTTPQUERYINFOW)GetProcAddress(module, "HttpQueryInfoW") : NULL;
    close_handle = module ? (PFNINTERNETCLOSEHANDLE)GetProcAddress(module, "InternetCloseHandle") : NULL;
    if (proxy_port)
    {
        swprintf(proxy, sizeof(proxy) / sizeof(proxy[0]), L"127.0.0.1:%u", proxy_port);
        access_type = VKMT_INTERNET_OPEN_TYPE_PROXY;
        proxy_name = proxy;
    }
    internet = internet_open ? internet_open(L"VKMT-TLS-Contract/1.0",
                                              access_type, proxy_name, NULL, 0) : NULL;
    url = internet && internet_open_url ? internet_open_url(internet, address, NULL, 0,
                                      VKMT_INTERNET_FLAG_RELOAD | VKMT_INTERNET_FLAG_NO_CACHE_WRITE |
                                      VKMT_INTERNET_FLAG_SECURE, 0) : NULL;
    if (url && query_info(url, VKMT_HTTP_QUERY_STATUS_CODE | VKMT_HTTP_QUERY_FLAG_NUMBER,
                              &status, &size, NULL))
        ok = status == 200;
    error = GetLastError();
    if (expected_valid)
    {
        if (ok) cap("WinINet", "PASS", 0, proxy_port ?
            "trusted localhost chain via fragmented CONNECT proxy" :
            "trusted localhost chain and hostname");
        else fail("WinINet", error, "valid chain rejected");
    }
    else if (!ok)
        cap("WinINet", "PASS", error, "invalid certificate rejected");
    else
        fail("WinINet", 0, "invalid certificate accepted");
    if (url && close_handle) close_handle(url);
    if (internet && close_handle) close_handle(internet);
    if (module) FreeLibrary(module);
    return ok == expected_valid;
}

static HCERTSTORE open_root_store(void)
{
    return CertOpenStore(CERT_STORE_PROV_SYSTEM_W,
                         X509_ASN_ENCODING | PKCS_7_ASN_ENCODING, 0,
                         CERT_SYSTEM_STORE_CURRENT_USER | CERT_STORE_MAXIMUM_ALLOWED_FLAG,
                         L"ROOT");
}

static int remove_trust_material(const char *root_path, const char *crl_path)
{
    unsigned char *encoded, *crl_encoded;
    DWORD size, crl_size;
    PCCERT_CONTEXT certificate, found_certificate;
    PCCRL_CONTEXT crl, found_crl;
    HCERTSTORE store;
    int result = 0;

    encoded = read_file(root_path, &size);
    crl_encoded = strcmp(crl_path, "-") ? read_file(crl_path, &crl_size) : NULL;
    store = open_root_store();
    certificate = encoded ? CertCreateCertificateContext(
        X509_ASN_ENCODING | PKCS_7_ASN_ENCODING, encoded, size) : NULL;
    crl = crl_encoded ? CertCreateCRLContext(
        X509_ASN_ENCODING | PKCS_7_ASN_ENCODING, crl_encoded, crl_size) : NULL;
    found_certificate = store && certificate ? CertFindCertificateInStore(
        store, X509_ASN_ENCODING | PKCS_7_ASN_ENCODING, 0,
        CERT_FIND_EXISTING, certificate, NULL) : NULL;
    found_crl = store && crl ? CertFindCRLInStore(
        store, X509_ASN_ENCODING | PKCS_7_ASN_ENCODING, 0,
        CRL_FIND_EXISTING, crl, NULL) : NULL;
    if (found_crl && !CertDeleteCRLFromStore(found_crl)) result = 1;
    if (found_certificate && !CertDeleteCertificateFromStore(found_certificate)) result = 1;
    if (certificate) CertFreeCertificateContext(certificate);
    if (crl) CertFreeCRLContext(crl);
    if (store) CertCloseStore(store, 0);
    free(encoded);
    free(crl_encoded);
    return result;
}

int main(int argc, char **argv)
{
    HCERTSTORE store = NULL;
    PCCERT_CONTEXT root = NULL;
    unsigned short port;
    int expected_valid;
    int preinstalled = 0;
    int i;

    setvbuf(stdout, NULL, _IONBF, 0);
    if (argc == 3 && !strcmp(argv[1], "install-root"))
    {
        root = install_root(argv[2], "-", &store);
        if (!root) return 1;
        CertFreeCertificateContext(root);
        CertCloseStore(store, 0);
        puts("TLS_ROOT_INSTALL_OK");
        return 0;
    }
    if (argc == 3 && !strcmp(argv[1], "remove-root"))
    {
        if (remove_trust_material(argv[2], "-"))
        {
            fprintf(stderr, "TLS_ROOT_REMOVE_FAIL error=%lu\n", GetLastError());
            return 1;
        }
        puts("TLS_ROOT_REMOVE_OK");
        return 0;
    }
    if (argc == 4 && !strcmp(argv[1], "install"))
    {
        root = install_root(argv[2], argv[3], &store);
        if (!root) return 1;
        CertFreeCertificateContext(root);
        CertCloseStore(store, 0);
        puts("TLS_ROOT_INSTALL_OK");
        return 0;
    }
    if (argc == 4 && !strcmp(argv[1], "remove"))
    {
        if (remove_trust_material(argv[2], argv[3]))
        {
            fprintf(stderr, "TLS_ROOT_REMOVE_FAIL error=%lu\n", GetLastError());
            return 1;
        }
        puts("TLS_ROOT_REMOVE_OK");
        return 0;
    }
    if (argc < 5 || (strcmp(argv[1], "valid") && strcmp(argv[1], "valid-fragmented") &&
                      strcmp(argv[1], "expired") && strcmp(argv[1], "untrusted")))
    {
        fprintf(stderr, "usage: %s valid|valid-fragmented|expired|untrusted PORT ROOT_DER CRL_DER [preinstalled] [proxy=PORT]\n", argv[0]);
        return 2;
    }
    port = (unsigned short)strtoul(argv[2], NULL, 10);
    expected_valid = !strcmp(argv[1], "valid") || !strcmp(argv[1], "valid-fragmented");
    for (i = 5; i < argc; ++i)
    {
        if (!strcmp(argv[i], "preinstalled")) preinstalled = 1;
        else if (!strncmp(argv[i], "proxy=", 6))
            proxy_port = (unsigned short)strtoul(argv[i] + 6, NULL, 10);
    }
    if (expected_valid && !preinstalled)
    {
        root = install_root(argv[3], argv[4], &store);
        if (!root) return 1;
    }
    cap("fixture", "PASS", 0, expected_valid ?
        (proxy_port ? "valid local trust through fragmented proxy" : "valid local trust") : argv[1]);
    winhttp_request(port, expected_valid);
    wininet_request(port, expected_valid);
    if (root) CertDeleteCertificateFromStore(root);
    if (store) CertCloseStore(store, 0);
    if (failures)
    {
        fprintf(stderr, "TLS_TRUST_CONTRACT_FAIL failures=%u\n", failures);
        return 1;
    }
    puts("TLS_TRUST_CONTRACT_OK");
    return 0;
}
