#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <stdio.h>

#define CONNECTIONS 32

int main(int argc, char **argv)
{
    const char *address = argc > 1 ? argv[1] : "104.20.23.154";
    WSANETWORKEVENTS network_events;
    WSAEVENT events[CONNECTIONS];
    SOCKET sockets[CONNECTIONS];
    struct sockaddr_storage remote = {0};
    int remote_size;
    int family;
    WSADATA data;

    family = strchr(address, ':') ? AF_INET6 : AF_INET;
    if (family == AF_INET6) {
        struct sockaddr_in6 *addr = (struct sockaddr_in6 *)&remote;
        addr->sin6_family = AF_INET6;
        addr->sin6_port = htons(443);
        remote_size = sizeof(*addr);
        if (InetPtonA(family, address, &addr->sin6_addr) != 1) return 10;
    } else {
        struct sockaddr_in *addr = (struct sockaddr_in *)&remote;
        addr->sin_family = AF_INET;
        addr->sin_port = htons(443);
        remote_size = sizeof(*addr);
        if (InetPtonA(family, address, &addr->sin_addr) != 1) return 11;
    }
    if (WSAStartup(MAKEWORD(2, 2), &data)) return 12;

    for (int i = 0; i < CONNECTIONS; ++i) {
        sockets[i] = socket(family, SOCK_STREAM, IPPROTO_TCP);
        events[i] = WSACreateEvent();
        if (sockets[i] == INVALID_SOCKET || events[i] == WSA_INVALID_EVENT) return 13;
        if (WSAEventSelect(sockets[i], events[i], FD_CONNECT | FD_CLOSE)) return 14;
        if (connect(sockets[i], (struct sockaddr *)&remote, remote_size) == SOCKET_ERROR &&
            WSAGetLastError() != WSAEWOULDBLOCK) {
            fprintf(stderr, "connect[%d] error=%d\n", i, WSAGetLastError());
            return 15;
        }
    }
    for (int remaining = CONNECTIONS; remaining; --remaining) {
        DWORD index = WSAWaitForMultipleEvents(CONNECTIONS, events, FALSE, 15000, FALSE);
        if (index < WSA_WAIT_EVENT_0 || index >= WSA_WAIT_EVENT_0 + CONNECTIONS) {
            fprintf(stderr, "wait timeout/error remaining=%d result=%lu error=%d\n",
                    remaining, (unsigned long)index, WSAGetLastError());
            return 16;
        }
        index -= WSA_WAIT_EVENT_0;
        if (WSAEnumNetworkEvents(sockets[index], events[index], &network_events)) return 17;
        if (!(network_events.lNetworkEvents & FD_CONNECT) ||
            network_events.iErrorCode[FD_CONNECT_BIT]) {
            fprintf(stderr, "events[%lu]=%lx connect_error=%d\n", (unsigned long)index,
                    network_events.lNetworkEvents, network_events.iErrorCode[FD_CONNECT_BIT]);
            return 18;
        }
    }
    for (int i = 0; i < CONNECTIONS; ++i) {
        closesocket(sockets[i]);
        WSACloseEvent(events[i]);
    }
    WSACleanup();
    puts("VKMT_PARALLEL_EVENT_CONNECT_OK count=32");
    return 0;
}
