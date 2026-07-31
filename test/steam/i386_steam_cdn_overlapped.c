#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdio.h>
#include <string.h>

static volatile LONG completed;
static volatile DWORD callback_error;
static volatile DWORD callback_bytes;

static void CALLBACK recv_complete(DWORD error, DWORD bytes, WSAOVERLAPPED *overlapped, DWORD flags)
{
    (void)overlapped;
    (void)flags;
    callback_error = error;
    callback_bytes = bytes;
    InterlockedExchange(&completed, 1);
}

int main(void)
{
    static const char request[] =
        "GET /client/resources_hidpi_all.zip.vz."
        "3de815c3117712cb9eeb7ea4c8b275faf481dcfd_56342 HTTP/1.1\r\n"
        "Host: cdn.steamstatic.com\r\nConnection: close\r\n\r\n";
    WSADATA data;
    struct addrinfo hints = {0}, *addresses = NULL, *it;
    SOCKET s = INVALID_SOCKET;
    WSAOVERLAPPED overlapped = {0};
    WSABUF buffer;
    char bytes[16384];
    DWORD flags, immediate;
    int ret, attempts, rounds = 0, total = 0;

    if (WSAStartup(MAKEWORD(2, 2), &data)) return 1;
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    if (getaddrinfo("cdn.steamstatic.com", "80", &hints, &addresses)) return 2;
    for (it = addresses; it; it = it->ai_next)
    {
        s = WSASocketW(it->ai_family, it->ai_socktype, it->ai_protocol,
                       NULL, 0, WSA_FLAG_OVERLAPPED);
        if (s != INVALID_SOCKET && !connect(s, it->ai_addr, (int)it->ai_addrlen)) break;
        if (s != INVALID_SOCKET) closesocket(s);
        s = INVALID_SOCKET;
    }
    freeaddrinfo(addresses);
    if (s == INVALID_SOCKET)
    {
        printf("CDN_OVERLAPPED_FAIL connect=%d\n", WSAGetLastError());
        return 3;
    }
    if (send(s, request, sizeof(request) - 1, 0) != sizeof(request) - 1)
    {
        printf("CDN_OVERLAPPED_FAIL send=%d\n", WSAGetLastError());
        return 4;
    }

    for (;;)
    {
        memset(&overlapped, 0, sizeof(overlapped));
        completed = 0;
        callback_error = 0xdeadbeef;
        callback_bytes = 0xdeadbeef;
        flags = 0;
        immediate = 0;
        buffer.buf = bytes;
        buffer.len = sizeof(bytes);
        ret = WSARecv(s, &buffer, 1, &immediate, &flags, &overlapped, recv_complete);
        if (ret && WSAGetLastError() != WSA_IO_PENDING)
        {
            printf("CDN_OVERLAPPED_FAIL issue round=%d error=%d\n",
                   rounds, WSAGetLastError());
            return 5;
        }

        for (attempts = 0; attempts < 100 && !completed; ++attempts) SleepEx(100, TRUE);
        printf("round=%d callback=%ld error=%lu bytes=%lu ov_status=%08lx "
               "ov_bytes=%lu attempts=%d\n", rounds, completed, callback_error,
               callback_bytes, (unsigned long)overlapped.Internal,
               (unsigned long)overlapped.InternalHigh, attempts);
        if (!completed || callback_error ||
            callback_bytes != overlapped.InternalHigh)
        {
            puts("CDN_OVERLAPPED_FAIL completion");
            return 6;
        }
        if (!rounds && (callback_bytes < 12 || memcmp(bytes, "HTTP/1.1 200", 12)))
        {
            puts("CDN_OVERLAPPED_FAIL response");
            return 7;
        }
        ++rounds;
        total += callback_bytes;
        if (!callback_bytes) break;
    }
    closesocket(s);
    WSACleanup();
    printf("rounds=%d total=%d\n", rounds, total);
    if (rounds < 3 || total < 56342)
    {
        puts("CDN_OVERLAPPED_FAIL incomplete");
        return 8;
    }
    puts("CDN_OVERLAPPED_OK");
    return 0;
}
