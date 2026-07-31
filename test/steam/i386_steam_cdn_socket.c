#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdio.h>
#include <string.h>

static const char host[] = "cdn.steamstatic.com";
static const char path[] =
    "/client/resources_hidpi_all.zip.vz."
    "3de815c3117712cb9eeb7ea4c8b275faf481dcfd_56342";

static int wait_socket(SOCKET s, int write)
{
    fd_set readfds, writefds, exceptfds;
    struct timeval timeout = {10, 0};
    int ret;

    FD_ZERO(&readfds);
    FD_ZERO(&writefds);
    FD_ZERO(&exceptfds);
    if (write) FD_SET(s, &writefds);
    else FD_SET(s, &readfds);
    FD_SET(s, &exceptfds);
    ret = select(0, write ? NULL : &readfds, write ? &writefds : NULL,
                 &exceptfds, &timeout);
    printf("select mode=%s ret=%d read=%d write=%d except=%d error=%d\n",
           write ? "write" : "read", ret, FD_ISSET(s, &readfds),
           FD_ISSET(s, &writefds), FD_ISSET(s, &exceptfds), WSAGetLastError());
    return ret;
}

int main(void)
{
    WSADATA data;
    struct addrinfo hints = {0}, *addresses = NULL, *it;
    SOCKET socket_handle = INVALID_SOCKET;
    u_long nonblocking = 1;
    char request[1024], buffer[16384];
    int ret, total = 0, header_done = 0;

    if (WSAStartup(MAKEWORD(2, 2), &data)) return 1;
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    if (getaddrinfo(host, "80", &hints, &addresses))
    {
        printf("CDN_SOCKET_FAIL getaddrinfo=%d\n", WSAGetLastError());
        return 2;
    }

    for (it = addresses; it; it = it->ai_next)
    {
        socket_handle = socket(it->ai_family, it->ai_socktype, it->ai_protocol);
        if (socket_handle == INVALID_SOCKET) continue;
        ioctlsocket(socket_handle, FIONBIO, &nonblocking);
        ret = connect(socket_handle, it->ai_addr, (int)it->ai_addrlen);
        printf("connect ret=%d error=%d family=%d socket=%Ix\n",
               ret, WSAGetLastError(), it->ai_family, (UINT_PTR)socket_handle);
        if (!ret || WSAGetLastError() == WSAEWOULDBLOCK)
        {
            if (wait_socket(socket_handle, 1) > 0) break;
        }
        closesocket(socket_handle);
        socket_handle = INVALID_SOCKET;
    }
    freeaddrinfo(addresses);
    if (socket_handle == INVALID_SOCKET)
    {
        puts("CDN_SOCKET_FAIL connect");
        return 3;
    }

    ret = snprintf(request, sizeof(request),
                   "GET %s HTTP/1.1\r\nHost: %s\r\n"
                   "Connection: close\r\nUser-Agent: VKMT-Steam-CDN-Probe\r\n\r\n",
                   path, host);
    if (send(socket_handle, request, ret, 0) <= 0)
    {
        printf("CDN_SOCKET_FAIL send=%d\n", WSAGetLastError());
        return 4;
    }

    while (wait_socket(socket_handle, 0) > 0)
    {
        ret = recv(socket_handle, buffer, sizeof(buffer), 0);
        printf("recv ret=%d error=%d\n", ret, WSAGetLastError());
        if (!ret) break;
        if (ret < 0)
        {
            if (WSAGetLastError() == WSAEWOULDBLOCK) continue;
            return 5;
        }
        total += ret;
        if (!header_done && total >= 12)
        {
            if (memcmp(buffer, "HTTP/1.1 200", 12))
            {
                fwrite(buffer, 1, min(ret, 256), stdout);
                puts("\nCDN_SOCKET_FAIL response");
                return 6;
            }
            header_done = 1;
        }
    }

    closesocket(socket_handle);
    WSACleanup();
    printf("total=%d\n", total);
    if (!header_done || total < 56342)
    {
        puts("CDN_SOCKET_FAIL incomplete");
        return 7;
    }
    puts("CDN_SOCKET_OK");
    return 0;
}
