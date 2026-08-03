#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>

#include <openssl/err.h>
#include <openssl/pool.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/*
 * Exercise Chromium's important TLS shape, not merely BoringSSL primitives:
 * pause SSL_connect from a custom certificate callback, verify on a worker
 * sequence, post the reply to the initiating sequence, and re-enter the
 * handshake.  The SRW/condition-variable queue is intentionally close to the
 * wait/wake contract used by Chromium's task scheduler on Windows.
 */
struct async_verify_state
{
    SRWLOCK lock;
    CONDITION_VARIABLE work_cv;
    CONDITION_VARIABLE reply_cv;
    X509 *certificate;
    HANDLE worker;
    LONG request_pending;
    LONG reply_ready;
    LONG shutting_down;
    int verify_ok;
};

static struct async_verify_state verify_state;

static DWORD WINAPI verify_worker(void *opaque)
{
    struct async_verify_state *state = opaque;

    AcquireSRWLockExclusive(&state->lock);
    while (!state->shutting_down)
    {
        X509 *certificate;
        EVP_PKEY *public_key;
        int ok;

        while (!state->request_pending && !state->shutting_down)
        {
            if (!SleepConditionVariableSRW(&state->work_cv, &state->lock,
                                           10000, 0) &&
                GetLastError() != ERROR_TIMEOUT)
            {
                state->verify_ok = 0;
                state->reply_ready = 1;
                WakeConditionVariable(&state->reply_cv);
                break;
            }
        }
        if (state->shutting_down) break;
        if (!state->request_pending) continue;

        certificate = state->certificate;
        state->certificate = NULL;
        state->request_pending = 0;
        ReleaseSRWLockExclusive(&state->lock);

        public_key = X509_get_pubkey(certificate);
        ok = public_key && X509_verify(certificate, public_key) == 1;
        if (public_key) EVP_PKEY_free(public_key);
        X509_free(certificate);

        AcquireSRWLockExclusive(&state->lock);
        state->verify_ok = ok;
        MemoryBarrier();
        state->reply_ready = 1;
        WakeConditionVariable(&state->reply_cv);
    }
    ReleaseSRWLockExclusive(&state->lock);
    return 0;
}

static enum ssl_verify_result_t custom_verify(SSL *ssl, uint8_t *out_alert)
{
    const STACK_OF(CRYPTO_BUFFER) *chain;
    const CRYPTO_BUFFER *leaf_buffer;
    const uint8_t *der;
    X509 *leaf;

    (void)out_alert;
    AcquireSRWLockExclusive(&verify_state.lock);
    if (verify_state.reply_ready)
    {
        int ok = verify_state.verify_ok;
        ReleaseSRWLockExclusive(&verify_state.lock);
        return ok ? ssl_verify_ok : ssl_verify_invalid;
    }
    if (!verify_state.request_pending)
    {
        chain = SSL_get0_peer_certificates(ssl);
        leaf_buffer = chain && sk_CRYPTO_BUFFER_num(chain)
                          ? sk_CRYPTO_BUFFER_value(chain, 0) : NULL;
        der = leaf_buffer ? CRYPTO_BUFFER_data(leaf_buffer) : NULL;
        leaf = leaf_buffer ? d2i_X509(NULL, &der,
                                     CRYPTO_BUFFER_len(leaf_buffer)) : NULL;
        if (!leaf)
        {
            ReleaseSRWLockExclusive(&verify_state.lock);
            return ssl_verify_invalid;
        }
        verify_state.certificate = leaf;
        verify_state.request_pending = 1;
        WakeConditionVariable(&verify_state.work_cv);
    }
    ReleaseSRWLockExclusive(&verify_state.lock);
    return ssl_verify_retry;
}

static int wait_for_verification_reply(void)
{
    BOOL ret = TRUE;

    AcquireSRWLockExclusive(&verify_state.lock);
    while (!verify_state.reply_ready && ret)
        ret = SleepConditionVariableSRW(&verify_state.reply_cv,
                                        &verify_state.lock, 10000, 0);
    ReleaseSRWLockExclusive(&verify_state.lock);
    if (!ret)
        fprintf(stderr, "VKMT_BORINGSSL_ASYNC_FAILED stage=reply_wait error=%lu\n",
                (unsigned long)GetLastError());
    return ret;
}

static void print_ssl_error(const char *stage, SSL *ssl, int result)
{
    unsigned long error;
    fprintf(stderr, "VKMT_BORINGSSL_ASYNC_FAILED stage=%s result=%d ssl_error=%d winsock=%d\n",
            stage, result, ssl ? SSL_get_error(ssl, result) : 0,
            WSAGetLastError());
    while ((error = ERR_get_error()) != 0)
    {
        char text[256];
        ERR_error_string_n(error, text, sizeof(text));
        fprintf(stderr, "BORINGSSL_ERROR %s\n", text);
    }
}

int main(int argc, char **argv)
{
    const char request[] =
        "GET / HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n";
    struct sockaddr_in address;
    WSADATA winsock;
    SSL_CTX *context = NULL;
    SSL *ssl = NULL;
    SOCKET socket_fd = INVALID_SOCKET;
    char response[4096];
    int port = argc > 1 ? atoi(argv[1]) : 19445;
    int result;
    int status = 2;

    InitializeSRWLock(&verify_state.lock);
    InitializeConditionVariable(&verify_state.work_cv);
    InitializeConditionVariable(&verify_state.reply_cv);
    verify_state.worker = CreateThread(NULL, 0, verify_worker, &verify_state, 0, NULL);
    if (!verify_state.worker)
    {
        fputs("VKMT_BORINGSSL_ASYNC_FAILED stage=worker_create\n", stderr);
        return status;
    }

    if (WSAStartup(MAKEWORD(2, 2), &winsock) != 0) goto done;
    socket_fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (socket_fd == INVALID_SOCKET) goto done;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons((unsigned short)port);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (connect(socket_fd, (const struct sockaddr *)&address, sizeof(address)) == SOCKET_ERROR)
    {
        print_ssl_error("connect", NULL, 0);
        goto done;
    }

    context = SSL_CTX_new(TLS_client_method());
    ssl = context ? SSL_new(context) : NULL;
    if (!ssl) goto done;
    SSL_set_custom_verify(ssl, SSL_VERIFY_PEER, custom_verify);
    SSL_set_tlsext_host_name(ssl, "localhost");
    if (!SSL_set_fd(ssl, (int)socket_fd)) goto done;

    result = SSL_connect(ssl);
    if (result != -1 || SSL_get_error(ssl, result) != SSL_ERROR_WANT_CERTIFICATE_VERIFY)
    {
        print_ssl_error("expected_verify_pause", ssl, result);
        goto done;
    }
    if (!wait_for_verification_reply()) goto done;
    result = SSL_connect(ssl);
    if (result != 1)
    {
        print_ssl_error("resume_SSL_connect", ssl, result);
        goto done;
    }
    result = SSL_write(ssl, request, (int)strlen(request));
    if (result <= 0) goto done;
    result = SSL_read(ssl, response, sizeof(response) - 1);
    if (result <= 0) goto done;
    response[result] = 0;
    if (!strstr(response, "HTTP/")) goto done;

    printf("VKMT_BORINGSSL_ASYNC_OK protocol=%s cipher=%s bytes=%d\n",
           SSL_get_version(ssl), SSL_get_cipher(ssl), result);
    status = 0;

done:
    if (ssl) SSL_free(ssl);
    if (context) SSL_CTX_free(context);
    if (socket_fd != INVALID_SOCKET) closesocket(socket_fd);
    WSACleanup();

    AcquireSRWLockExclusive(&verify_state.lock);
    verify_state.shutting_down = 1;
    WakeAllConditionVariable(&verify_state.work_cv);
    ReleaseSRWLockExclusive(&verify_state.lock);
    WaitForSingleObject(verify_state.worker, 10000);
    CloseHandle(verify_state.worker);
    if (verify_state.certificate) X509_free(verify_state.certificate);
    return status;
}
