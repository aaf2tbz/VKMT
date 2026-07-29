#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <stdio.h>

int wmain( void )
{
    ADDRINFOW hints, *result = NULL, *entry;
    WCHAR address[64];
    DWORD address_len;
    WSADATA data;
    int count = 0, status;

    if (WSAStartup( MAKEWORD(2, 2), &data ))
    {
        fprintf( stderr, "I386_DNS_FAIL stage=startup error=%d\n", WSAGetLastError() );
        return 1;
    }
    memset( &hints, 0, sizeof(hints) );
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    status = GetAddrInfoW( L"example.com", NULL, &hints, &result );
    if (status)
    {
        fprintf( stderr, "I386_DNS_FAIL stage=resolve status=%d error=%d\n",
                 status, WSAGetLastError() );
        WSACleanup();
        return 1;
    }

    for (entry = result; entry; entry = entry->ai_next)
    {
        address_len = sizeof(address) / sizeof(address[0]);
        if (!WSAAddressToStringW( entry->ai_addr, entry->ai_addrlen, NULL,
                                  address, &address_len ))
            ++count;
    }
    FreeAddrInfoW( result );
    WSACleanup();
    if (!count)
    {
        fprintf( stderr, "I386_DNS_FAIL stage=enumerate\n" );
        return 1;
    }
    printf( "I386_DNS_OK addresses=%d\n", count );
    return 0;
}
