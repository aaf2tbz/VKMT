/* Native AArch64 PE acceptance fixture for the VKMT Wine host. */
#include <windows.h>

int main(void)
{
    static const char message[] = "VKMT native AArch64 smoke passed\r\n";
    DWORD written = 0;

    if (!WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), message,
                   sizeof(message) - 1, &written, NULL))
        return 2;
    return written == sizeof(message) - 1 ? 0 : 3;
}
