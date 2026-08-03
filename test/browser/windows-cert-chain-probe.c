#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wincrypt.h>

#include <stdio.h>
#include <stdlib.h>

static unsigned char *read_file(const char *path, DWORD *size)
{
    HANDLE file = CreateFileA(path, GENERIC_READ, FILE_SHARE_READ, NULL,
                              OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    LARGE_INTEGER length;
    unsigned char *data;
    DWORD read;
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

int main(int argc, char **argv)
{
    CERT_CHAIN_PARA chain_parameters = {sizeof(chain_parameters)};
    CERT_CHAIN_POLICY_PARA policy_parameters = {sizeof(policy_parameters)};
    CERT_CHAIN_POLICY_STATUS policy_status = {sizeof(policy_status)};
    PCCERT_CHAIN_CONTEXT chain = NULL;
    PCCERT_CONTEXT certificate;
    unsigned char *encoded;
    ULONGLONG started;
    DWORD encoded_size;
    BOOL verified;

    if (argc != 2 || !(encoded = read_file(argv[1], &encoded_size)))
    {
        fprintf(stderr, "VKMT_CERT_CHAIN_FAILED stage=read error=%lu\n", GetLastError());
        return 2;
    }
    certificate = CertCreateCertificateContext(X509_ASN_ENCODING | PKCS_7_ASN_ENCODING,
                                                encoded, encoded_size);
    free(encoded);
    if (!certificate)
    {
        fprintf(stderr, "VKMT_CERT_CHAIN_FAILED stage=parse error=%lu\n", GetLastError());
        return 3;
    }

    started = GetTickCount64();
    verified = CryptVerifyCertificateSignatureEx(0, X509_ASN_ENCODING,
                                                  CRYPT_VERIFY_CERT_SIGN_SUBJECT_CERT,
                                                  (void *)certificate,
                                                  CRYPT_VERIFY_CERT_SIGN_ISSUER_CERT,
                                                  (void *)certificate, 0, NULL);
    printf("VKMT_CERT_SIGNATURE_RESULT ok=%d error=%lu elapsed_ms=%llu oid=%s\n",
           verified, GetLastError(), GetTickCount64() - started,
           certificate->pCertInfo->SubjectPublicKeyInfo.Algorithm.pszObjId);

    started = GetTickCount64();
    verified = CertGetCertificateChain(NULL, certificate, NULL, certificate->hCertStore,
                                       &chain_parameters, CERT_CHAIN_CACHE_ONLY_URL_RETRIEVAL,
                                       NULL, &chain);
    printf("VKMT_CERT_CHAIN_RESULT ok=%d error=%lu elapsed_ms=%llu status=%#lx\n",
           verified, GetLastError(), GetTickCount64() - started,
           chain ? (unsigned long)chain->TrustStatus.dwErrorStatus : 0ul);
    if (!verified || !chain)
    {
        CertFreeCertificateContext(certificate);
        return 4;
    }

    started = GetTickCount64();
    verified = CertVerifyCertificateChainPolicy(CERT_CHAIN_POLICY_SSL, chain,
                                                &policy_parameters, &policy_status);
    printf("VKMT_CERT_POLICY_RESULT ok=%d api_error=%lu policy_error=%lu elapsed_ms=%llu\n",
           verified, GetLastError(), policy_status.dwError,
           GetTickCount64() - started);
    CertFreeCertificateChain(chain);
    CertFreeCertificateContext(certificate);
    puts("VKMT_CERT_CHAIN_OK");
    return 0;
}
