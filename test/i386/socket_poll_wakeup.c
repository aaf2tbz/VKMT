#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#include <stdio.h>

struct poll_context
{
    SOCKET socket;
    int poll_result;
    int recv_result;
    int error;
    char byte;
};

static DWORD WINAPI poll_thread( void *opaque )
{
    struct poll_context *context = opaque;
    WSAPOLLFD pollfd;

    pollfd.fd = context->socket;
    pollfd.events = POLLRDNORM;
    pollfd.revents = 0;
    context->poll_result = WSAPoll( &pollfd, 1, 5000 );
    if (context->poll_result == SOCKET_ERROR)
    {
        context->error = WSAGetLastError();
        return 1;
    }
    if (context->poll_result != 1 || !(pollfd.revents & POLLRDNORM))
        return 2;
    context->recv_result = recv( context->socket, &context->byte, 1, 0 );
    if (context->recv_result != 1)
    {
        context->error = WSAGetLastError();
        return 3;
    }
    return 0;
}

int main( void )
{
    struct poll_context context = { .socket = INVALID_SOCKET };
    struct sockaddr_in address;
    int address_size = sizeof(address);
    WSADATA data;
    SOCKET listener = INVALID_SOCKET, client = INVALID_SOCKET;
    HANDLE thread = NULL;
    DWORD thread_result = ~0u;
    char byte = 'W';
    const char *stage = "startup";
    int ret = 1;

    if (WSAStartup( MAKEWORD(2, 2), &data ))
    {
        fprintf( stderr, "I386_SOCKET_POLL_FAIL stage=startup\n" );
        return 1;
    }
    stage = "listener_socket";
    listener = socket( AF_INET, SOCK_STREAM, IPPROTO_TCP );
    if (listener == INVALID_SOCKET) goto failed;
    memset( &address, 0, sizeof(address) );
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl( INADDR_LOOPBACK );
    stage = "bind";
    if (bind( listener, (struct sockaddr *)&address, sizeof(address) )) goto failed;
    stage = "listen";
    if (listen( listener, 1 )) goto failed;
    stage = "getsockname";
    if (getsockname( listener, (struct sockaddr *)&address, &address_size )) goto failed;

    stage = "client_socket";
    client = socket( AF_INET, SOCK_STREAM, IPPROTO_TCP );
    if (client == INVALID_SOCKET) goto failed;
    stage = "connect";
    if (connect( client, (struct sockaddr *)&address, sizeof(address) )) goto failed;
    stage = "accept";
    context.socket = accept( listener, NULL, NULL );
    if (context.socket == INVALID_SOCKET) goto failed;

    stage = "create_thread";
    thread = CreateThread( NULL, 0, poll_thread, &context, 0, NULL );
    if (!thread) goto failed;
    Sleep( 100 );
    stage = "send";
    if (send( client, &byte, 1, 0 ) != 1) goto failed;
    stage = "wait";
    if (WaitForSingleObject( thread, 10000 ) != WAIT_OBJECT_0 ||
        !GetExitCodeThread( thread, &thread_result ) || thread_result)
        goto failed;

    printf( "I386_SOCKET_POLL_OK poll=%d recv=%d byte=%c\n",
            context.poll_result, context.recv_result, context.byte );
    ret = 0;
    goto done;

failed:
    fprintf( stderr,
             "I386_SOCKET_POLL_FAIL stage=%s winerr=%lu wsa=%d thread=%lu poll=%d recv=%d worker_wsa=%d\n",
             stage, GetLastError(), WSAGetLastError(), thread_result,
             context.poll_result, context.recv_result, context.error );
done:
    if (thread) CloseHandle( thread );
    if (context.socket != INVALID_SOCKET) closesocket( context.socket );
    if (client != INVALID_SOCKET) closesocket( client );
    if (listener != INVALID_SOCKET) closesocket( listener );
    WSACleanup();
    return ret;
}
