#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <windows.h>
#include <stdio.h>
#include <string.h>

struct client_args
{
    unsigned short port;
    int result;
};

static DWORD WINAPI client_thread(void *opaque)
{
    struct client_args *args = opaque;
    struct sockaddr_in addr;
    char reply[128] = {0};
    SOCKET socket_handle;
    int length;

    socket_handle = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (socket_handle == INVALID_SOCKET) return 10;
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons(args->port);
    if (connect(socket_handle, (struct sockaddr *)&addr, sizeof(addr)))
    {
        args->result = WSAGetLastError();
        closesocket(socket_handle);
        return 11;
    }
    if (send(socket_handle, "GET / HTTP/1.0\r\n\r\n", 18, 0) != 18)
    {
        args->result = WSAGetLastError();
        closesocket(socket_handle);
        return 12;
    }
    length = recv(socket_handle, reply, sizeof(reply) - 1, 0);
    if (length <= 0 || !strstr(reply, "VKMT_WS2_OK"))
    {
        args->result = length < 0 ? WSAGetLastError() : length;
        closesocket(socket_handle);
        return 13;
    }
    closesocket(socket_handle);
    args->result = 0;
    return 0;
}

int main(void)
{
    static const char response[] =
        "HTTP/1.0 200 OK\r\nContent-Length: 11\r\n\r\nVKMT_WS2_OK";
    struct sockaddr_in addr;
    struct client_args args = {0};
    WSANETWORKEVENTS network_events;
    WSADATA data;
    HANDLE thread;
    WSAEVENT event;
    SOCKET listener, accepted;
    DWORD thread_status;
    int addr_length = sizeof(addr), length, attempt;
    int socket_error;
    char request[128];

    if (WSAStartup(MAKEWORD(2, 2), &data)) return 1;
    listener = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (listener == INVALID_SOCKET) return 2;
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = 0;
    if (bind(listener, (struct sockaddr *)&addr, sizeof(addr)) ||
        getsockname(listener, (struct sockaddr *)&addr, &addr_length) ||
        listen(listener, 1))
        return 3;

    event = WSACreateEvent();
    if (event == WSA_INVALID_EVENT ||
        WSAEventSelect(listener, event, FD_ACCEPT | FD_CLOSE))
        return 4;

    args.port = ntohs(addr.sin_port);
    thread = CreateThread(NULL, 0, client_thread, &args, 0, NULL);
    if (!thread) return 5;
    if (WSAWaitForMultipleEvents(1, &event, FALSE, 10000, FALSE) !=
        WSA_WAIT_EVENT_0)
        return 6;
    if (WSAEnumNetworkEvents(listener, event, &network_events))
    {
        printf("WS2_ENUM_FAILED socket=%p event=%p error=%d\n",
               (void *)listener, event, WSAGetLastError());
        return 7;
    }
    if (!(network_events.lNetworkEvents & FD_ACCEPT))
        return 8;

    accepted = accept(listener, NULL, NULL);
    if (accepted == INVALID_SOCKET) return 9;
    for (attempt = 0; attempt < 100; ++attempt)
    {
        length = recv(accepted, request, sizeof(request), 0);
        if (length > 0) break;
        socket_error = WSAGetLastError();
        if (!length || socket_error != WSAEWOULDBLOCK)
        {
            printf("WS2_SERVER_RECV_FAILED accepted=%p length=%d error=%d\n",
                   (void *)accepted, length, socket_error);
            return 10;
        }
        Sleep(10);
    }
    if (attempt == 100)
    {
        puts("WS2_SERVER_RECV_TIMEOUT");
        return 10;
    }
    length = send(accepted, response, sizeof(response) - 1, 0);
    if (length != sizeof(response) - 1)
    {
        printf("WS2_SERVER_SEND_FAILED accepted=%p length=%d error=%d\n",
               (void *)accepted, length, WSAGetLastError());
        return 10;
    }
    closesocket(accepted);
    closesocket(listener);
    WSACloseEvent(event);

    WaitForSingleObject(thread, 10000);
    GetExitCodeThread(thread, &thread_status);
    CloseHandle(thread);
    WSACleanup();
    if (thread_status || args.result)
    {
        printf("WS2_CLIENT_FAILED status=%lu error=%d\n",
               thread_status, args.result);
        return 11;
    }
    puts("I386_WS2_EVENT_HTTP_OK");
    return 0;
}
