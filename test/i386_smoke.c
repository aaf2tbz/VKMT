/* Minimal i386 PE fixture for the native ARM64 WoW64/FEX execution gate. */
#include <windows.h>

int main(void)
{
    const char message[] = "VKMT i386 WoW64 smoke passed\r\n";
    DWORD written;

    if (!WriteFile( GetStdHandle( STD_OUTPUT_HANDLE ), message, sizeof(message) - 1, &written, NULL ))
        return 2;
    return written == sizeof(message) - 1 ? 0 : 3;
}
