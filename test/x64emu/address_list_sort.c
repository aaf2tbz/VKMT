#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#include <stdio.h>

#ifndef SIO_ADDRESS_LIST_SORT
#define SIO_ADDRESS_LIST_SORT _WSAIORW(IOC_WS2, 25)
#endif

int main(void)
{
    struct
    {
        SOCKET_ADDRESS_LIST list;
        SOCKET_ADDRESS extra;
    } addresses;
    struct sockaddr_in ipv4 = {0};
    struct sockaddr_in6 ipv6 = {0};
    WSADATA data;
    DWORD bytes = 0;
    SOCKET socket_handle;
    int ret;

    if (WSAStartup(MAKEWORD(2, 2), &data)) return 10;
    socket_handle = socket(AF_INET6, SOCK_STREAM, IPPROTO_TCP);
    if (socket_handle == INVALID_SOCKET) return 11;

    ipv4.sin_family = AF_INET;
    ipv6.sin6_family = AF_INET6;
    addresses.list.iAddressCount = 2;
    addresses.list.Address[0].lpSockaddr = (SOCKADDR *)&ipv6;
    addresses.list.Address[0].iSockaddrLength = sizeof(ipv6);
    addresses.list.Address[1].lpSockaddr = (SOCKADDR *)&ipv4;
    addresses.list.Address[1].iSockaddrLength = sizeof(ipv4);

    ret = WSAIoctl(socket_handle, SIO_ADDRESS_LIST_SORT,
                   &addresses, sizeof(addresses),
                   &addresses, sizeof(addresses), &bytes, NULL, NULL);
    if (ret || addresses.list.Address[0].lpSockaddr->sa_family != AF_INET ||
        addresses.list.Address[1].lpSockaddr->sa_family != AF_INET6)
    {
        fprintf(stderr, "sort failed ret=%d error=%d bytes=%lu families=%u,%u\n",
                ret, WSAGetLastError(), (unsigned long)bytes,
                addresses.list.Address[0].lpSockaddr->sa_family,
                addresses.list.Address[1].lpSockaddr->sa_family);
        return 12;
    }
    closesocket(socket_handle);
    WSACleanup();
    puts("VKMT_ADDRESS_LIST_SORT_OK");
    return 0;
}
