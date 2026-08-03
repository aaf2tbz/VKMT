#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>

#include <openssl/err.h>
#include <openssl/ssl.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void print_ssl_error(const char *stage, SSL *ssl, int result)
{
    unsigned long error;
    fprintf(stderr, "VKMT_BORINGSSL_TLS_FAILED stage=%s result=%d ssl_error=%d winsock=%d\n",
            stage, result, ssl ? SSL_get_error(ssl, result) : 0, WSAGetLastError());
    while ((error = ERR_get_error()) != 0)
    {
        char text[256];
        ERR_error_string_n(error, text, sizeof(text));
        fprintf(stderr, "BORINGSSL_ERROR %s\n", text);
    }
}

int main(int argc, char **argv)
{
    const char request[] = "GET / HTTP/1.0\r\nHost: localhost\r\nConnection: close\r\n\r\n";
    struct sockaddr_in address;
    WSADATA winsock;
    SSL_CTX *context = NULL;
    SSL *ssl = NULL;
    SOCKET socket_fd = INVALID_SOCKET;
    char response[4096];
    int port = argc > 1 ? atoi(argv[1]) : 19445;
    int result;
    int status = 2;

    if (WSAStartup(MAKEWORD(2, 2), &winsock) != 0)
    {
        print_ssl_error("WSAStartup", NULL, 0);
        return status;
    }
    socket_fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (socket_fd == INVALID_SOCKET)
    {
        print_ssl_error("socket", NULL, 0);
        goto done;
    }
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
    if (!ssl)
    {
        print_ssl_error("SSL_new", ssl, 0);
        goto done;
    }
    SSL_CTX_set_verify(context, SSL_VERIFY_NONE, NULL);
    SSL_set_tlsext_host_name(ssl, "localhost");
    if (!SSL_set_fd(ssl, (int)socket_fd))
    {
        print_ssl_error("SSL_set_fd", ssl, 0);
        goto done;
    }
    result = SSL_connect(ssl);
    if (result != 1)
    {
        print_ssl_error("SSL_connect", ssl, result);
        goto done;
    }
    result = SSL_write(ssl, request, (int)strlen(request));
    if (result <= 0)
    {
        print_ssl_error("SSL_write", ssl, result);
        goto done;
    }
    result = SSL_read(ssl, response, sizeof(response) - 1);
    if (result <= 0)
    {
        print_ssl_error("SSL_read", ssl, result);
        goto done;
    }
    response[result] = 0;
    if (!strstr(response, "HTTP/"))
    {
        fputs("VKMT_BORINGSSL_TLS_FAILED stage=response\n", stderr);
        goto done;
    }
    printf("VKMT_BORINGSSL_TLS_OK protocol=%s cipher=%s bytes=%d\n",
           SSL_get_version(ssl), SSL_get_cipher(ssl), result);
    status = 0;

done:
    if (ssl) SSL_free(ssl);
    if (context) SSL_CTX_free(context);
    if (socket_fd != INVALID_SOCKET) closesocket(socket_fd);
    WSACleanup();
    return status;
}
