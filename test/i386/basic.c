#include <windows.h>

__declspec(noinline) static int stack_add(int a, int b)
{
    volatile int local = a + b;
    return local;
}

int main(void)
{
    int total = 0;
    int i;

    for (i = 0; i < 16; ++i)
        total += (i & 1) ? stack_add(i, 2) : -stack_add(i, -2);

    if (total != 40) return 10;
    if (!WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), "VKMT i386 basic passed\n",
                   sizeof("VKMT i386 basic passed\n") - 1, (DWORD *)&i, NULL))
        return 11;
    return 0;
}
