#include <jni.h>
#include <stdint.h>
#include <string.h>
#include <windows.h>

typedef int (__cdecl *generated_function)(void);

static void write_return_value(unsigned char *code, uint32_t value)
{
    code[0] = 0xb8; /* mov eax, imm32 */
    memcpy(code + 1, &value, sizeof(value));
    code[5] = 0xc3; /* ret */
}

static int call_generated(void *memory)
{
    union {
        void *object;
        generated_function function;
    } callable;
    callable.object = memory;
    return callable.function();
}

JNIEXPORT jlong JNICALL
Java_VkmtWindowsJavaJitProbe_nativeExecutableMemory(JNIEnv *environment,
                                                     jclass type,
                                                     jint iterations)
{
    SYSTEM_INFO system_info;
    unsigned char *code;
    DWORD old_protection;
    uint32_t patch;
    int index;

    (void)environment;
    (void)type;
    if (iterations <= 0) return 0;

    GetSystemInfo(&system_info);
    code = VirtualAlloc(NULL, system_info.dwPageSize, MEM_RESERVE | MEM_COMMIT,
                        PAGE_READWRITE);
    if (!code) return 0;

    write_return_value(code, 0);
    for (index = 0; index < iterations; ++index) {
        if (!VirtualProtect(code, system_info.dwPageSize, PAGE_EXECUTE_READ,
                            &old_protection))
            goto failure;
        if (!FlushInstructionCache(GetCurrentProcess(), code, 6))
            goto failure;
        if (call_generated(code) != index)
            goto failure;
        if (!VirtualProtect(code, system_info.dwPageSize, PAGE_READWRITE,
                            &old_protection))
            goto failure;
        patch = (uint32_t)index + 1;
        memcpy(code + 1, &patch, sizeof(patch));
        if (!FlushInstructionCache(GetCurrentProcess(), code, 6))
            goto failure;
    }

    if (!VirtualProtect(code, system_info.dwPageSize, PAGE_EXECUTE_READ,
                        &old_protection))
        goto failure;
    if (!FlushInstructionCache(GetCurrentProcess(), code, 6))
        goto failure;
    if (call_generated(code) != iterations)
        goto failure;
    VirtualFree(code, 0, MEM_RELEASE);
    return ((jlong)(uint32_t)iterations << 32) | (uint32_t)iterations;

failure:
    VirtualFree(code, 0, MEM_RELEASE);
    return 0;
}
