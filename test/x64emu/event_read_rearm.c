#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <stdio.h>

int main(void)
{
    struct sockaddr_in remote = {0};
    WSANETWORKEVENTS events;
    WSAEVENT event;
    WSADATA data;
    SOCKET socket_handle;
    char byte;
    int ret;

    if (WSAStartup(MAKEWORD(2, 2), &data)) return 10;
    socket_handle = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    event = WSACreateEvent();
    if (socket_handle == INVALID_SOCKET || event == WSA_INVALID_EVENT) return 11;
    if (WSAEventSelect(socket_handle, event, FD_CONNECT | FD_READ | FD_CLOSE)) return 12;
    remote.sin_family = AF_INET;
    remote.sin_port = htons(19446);
    InetPtonA(AF_INET, "127.0.0.1", &remote.sin_addr);
    ret = connect(socket_handle, (struct sockaddr *)&remote, sizeof(remote));
    if (ret == SOCKET_ERROR && WSAGetLastError() != WSAEWOULDBLOCK) return 13;
    if (WSAWaitForMultipleEvents(1, &event, FALSE, 5000, FALSE) != WSA_WAIT_EVENT_0) return 14;
    if (WSAEnumNetworkEvents(socket_handle, event, &events)) return 15;
    if (!(events.lNetworkEvents & FD_CONNECT) || events.iErrorCode[FD_CONNECT_BIT]) return 16;

    for (int expected = 'A'; expected <= 'B'; ++expected) {
        if (WSAWaitForMultipleEvents(1, &event, FALSE, 5000, FALSE) != WSA_WAIT_EVENT_0) {
            fprintf(stderr, "FD_READ rearm timeout expected=%c error=%d\n", expected, WSAGetLastError());
            return 17;
        }
        if (WSAEnumNetworkEvents(socket_handle, event, &events)) return 18;
        if (!(events.lNetworkEvents & FD_READ) || events.iErrorCode[FD_READ_BIT]) {
            fprintf(stderr, "read events=%lx error=%d expected=%c\n", events.lNetworkEvents,
                    events.iErrorCode[FD_READ_BIT], expected);
            return 19;
        }
        ret = recv(socket_handle, &byte, 1, 0);
        if (ret != 1 || byte != expected) {
            fprintf(stderr, "recv ret=%d byte=%d error=%d expected=%c\n",
                    ret, ret == 1 ? byte : -1, WSAGetLastError(), expected);
            return 20;
        }
    }
    puts("VKMT_EVENT_READ_REARM_OK");
    closesocket(socket_handle);
    WSACloseEvent(event);
    WSACleanup();
    return 0;
}
