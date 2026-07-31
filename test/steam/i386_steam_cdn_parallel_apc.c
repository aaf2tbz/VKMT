#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <stdio.h>
#include <stddef.h>
#include <string.h>

#define SLOT_COUNT 8

struct slot
{
    WSAOVERLAPPED overlapped;
    SOCKET socket;
    WSABUF wsabuf;
    char buffer[8192];
    LONG done;
    LONG failed;
    DWORD rounds;
    DWORD total;
};

static LONG done_count;

static void issue_receive(struct slot *slot);

static void CALLBACK recv_complete(DWORD error, DWORD bytes,
                                   WSAOVERLAPPED *overlapped, DWORD flags)
{
    struct slot *slot = (struct slot *)((char *)overlapped - offsetof(struct slot, overlapped));
    (void)flags;

    if (error || bytes != overlapped->InternalHigh)
    {
        printf("callback_fail slot=%ld error=%lu bytes=%lu status=%08lx ov_bytes=%lu\n",
               (long)(slot - (struct slot *)0), error, bytes,
               (unsigned long)overlapped->Internal,
               (unsigned long)overlapped->InternalHigh);
        InterlockedExchange(&slot->failed, 1);
    }
    slot->rounds++;
    slot->total += bytes;
    if (error || !bytes)
    {
        InterlockedExchange(&slot->done, 1);
        InterlockedIncrement(&done_count);
        return;
    }
    issue_receive(slot);
}

static void issue_receive(struct slot *slot)
{
    DWORD flags = 0, immediate = 0;
    int ret;

    memset(&slot->overlapped, 0, sizeof(slot->overlapped));
    slot->wsabuf.buf = slot->buffer;
    slot->wsabuf.len = sizeof(slot->buffer);
    ret = WSARecv(slot->socket, &slot->wsabuf, 1, &immediate, &flags,
                  &slot->overlapped, recv_complete);
    if (ret && WSAGetLastError() != WSA_IO_PENDING)
    {
        printf("issue_fail error=%d\n", WSAGetLastError());
        InterlockedExchange(&slot->failed, 1);
        InterlockedExchange(&slot->done, 1);
        InterlockedIncrement(&done_count);
    }
}

static SOCKET connect_cdn(const struct addrinfo *addresses)
{
    const struct addrinfo *it;
    SOCKET socket_handle;

    for (it = addresses; it; it = it->ai_next)
    {
        socket_handle = WSASocketW(it->ai_family, it->ai_socktype, it->ai_protocol,
                                   NULL, 0, WSA_FLAG_OVERLAPPED);
        if (socket_handle != INVALID_SOCKET &&
            !connect(socket_handle, it->ai_addr, (int)it->ai_addrlen))
            return socket_handle;
        if (socket_handle != INVALID_SOCKET) closesocket(socket_handle);
    }
    return INVALID_SOCKET;
}

int main(void)
{
    static const char request[] =
        "GET /client/resources_hidpi_all.zip.vz."
        "3de815c3117712cb9eeb7ea4c8b275faf481dcfd_56342 HTTP/1.1\r\n"
        "Host: cdn.steamstatic.com\r\nConnection: close\r\n\r\n";
    WSADATA data;
    struct addrinfo hints = {0}, *addresses = NULL;
    struct slot slots[SLOT_COUNT] = {{0}};
    int i, waits;

    if (WSAStartup(MAKEWORD(2, 2), &data)) return 1;
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    if (getaddrinfo("cdn.steamstatic.com", "80", &hints, &addresses)) return 2;

    for (i = 0; i < SLOT_COUNT; ++i)
    {
        slots[i].socket = connect_cdn(addresses);
        if (slots[i].socket == INVALID_SOCKET ||
            send(slots[i].socket, request, sizeof(request) - 1, 0) != sizeof(request) - 1)
        {
            printf("PARALLEL_APC_FAIL setup slot=%d error=%d\n", i, WSAGetLastError());
            return 3;
        }
        issue_receive(&slots[i]);
    }
    freeaddrinfo(addresses);

    for (waits = 0; waits < 300 && done_count != SLOT_COUNT; ++waits) SleepEx(100, TRUE);
    printf("done_count=%ld waits=%d\n", done_count, waits);
    for (i = 0; i < SLOT_COUNT; ++i)
    {
        printf("slot=%d done=%ld failed=%ld rounds=%lu total=%lu\n", i,
               slots[i].done, slots[i].failed, slots[i].rounds, slots[i].total);
        closesocket(slots[i].socket);
        if (!slots[i].done || slots[i].failed || slots[i].rounds < 3 ||
            slots[i].total < 56342)
            return 4;
    }
    WSACleanup();
    puts("CDN_PARALLEL_APC_OK");
    return 0;
}
