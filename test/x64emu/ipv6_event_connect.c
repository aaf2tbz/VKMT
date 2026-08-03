#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <stdio.h>

int main(int argc, char **argv)
{
    const char *address = argc > 1 ? argv[1] : "2606:4700:10::ac42:93f3";
    static const char request[] = "HEAD / HTTP/1.0\r\nHost: example.com\r\n\r\n";
    struct sockaddr_in6 remote = {0};
    WSANETWORKEVENTS events;
    WSADATA data;
    WSAEVENT event;
    SOCKET socket_handle;
    char reply[256];
    int ret;

    if (WSAStartup(MAKEWORD(2, 2), &data)) return 10;
    socket_handle = socket(AF_INET6, SOCK_STREAM, IPPROTO_TCP);
    if (socket_handle == INVALID_SOCKET) return 11;
    event = WSACreateEvent();
    if (event == WSA_INVALID_EVENT) return 12;
    if (WSAEventSelect(socket_handle, event, FD_CONNECT | FD_READ | FD_CLOSE)) return 13;

    remote.sin6_family = AF_INET6;
    remote.sin6_port = htons(80);
    if (InetPtonA(AF_INET6, address, &remote.sin6_addr) != 1) return 14;
    ret = connect(socket_handle, (struct sockaddr *)&remote, sizeof(remote));
    if (ret == SOCKET_ERROR && WSAGetLastError() != WSAEWOULDBLOCK) {
        fprintf(stderr, "connect error=%d\n", WSAGetLastError());
        return 15;
    }
    if (WSAWaitForMultipleEvents(1, &event, FALSE, 10000, FALSE) != WSA_WAIT_EVENT_0) {
        fprintf(stderr, "connect event timeout error=%d\n", WSAGetLastError());
        return 16;
    }
    if (WSAEnumNetworkEvents(socket_handle, event, &events)) return 17;
    if (!(events.lNetworkEvents & FD_CONNECT) || events.iErrorCode[FD_CONNECT_BIT]) {
        fprintf(stderr, "connect events=%lx error=%d\n", events.lNetworkEvents,
                events.iErrorCode[FD_CONNECT_BIT]);
        return 18;
    }
    if (send(socket_handle, request, sizeof(request) - 1, 0) <= 0) return 19;
    if (WSAWaitForMultipleEvents(1, &event, FALSE, 10000, FALSE) != WSA_WAIT_EVENT_0) return 20;
    if (WSAEnumNetworkEvents(socket_handle, event, &events)) return 21;
    if (!(events.lNetworkEvents & (FD_READ | FD_CLOSE))) return 22;
    ret = recv(socket_handle, reply, sizeof(reply), 0);
    if (ret <= 0) {
        fprintf(stderr, "recv ret=%d error=%d events=%lx\n", ret, WSAGetLastError(), events.lNetworkEvents);
        return 23;
    }

    printf("VKMT_IPV6_EVENT_CONNECT_OK bytes=%d\n", ret);
    closesocket(socket_handle);
    WSACloseEvent(event);
    WSACleanup();
    return 0;
}
