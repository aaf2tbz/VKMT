#include <jni.h>
#include <stdint.h>
#include <string.h>
#include <windows.h>

struct __attribute__((packed)) unaligned_publication {
    unsigned char pad;
    volatile uint32_t payload;
    volatile uint32_t sequence;
    volatile uint32_t acknowledged;
};

struct native_state {
    unsigned iterations;
    volatile LONG failure;
    struct unaligned_publication unaligned;
    __attribute__((aligned(64))) volatile uint32_t rep_payload[64];
    volatile uint32_t rep_sequence;
    volatile uint32_t rep_acknowledged;
};

static DWORD WINAPI producer(void *opaque)
{
    struct native_state *state = opaque;
    unsigned sequence;

    for (sequence = 1; sequence <= state->iterations; ++sequence) {
        uint32_t value = sequence ^ 0xa5a55a5aU;
        uint32_t fill = sequence * 0x01010101U;
        volatile uint32_t *destination;
        unsigned count;

        while (state->unaligned.acknowledged != sequence - 1)
            SwitchToThread();
        state->unaligned.payload = value;
        state->unaligned.sequence = sequence;

        while (state->rep_acknowledged != sequence - 1)
            SwitchToThread();
        destination = state->rep_payload;
        count = 64;
        __asm__ volatile("cld; rep stosl"
                         : "+D"(destination), "+c"(count)
                         : "a"(fill) : "memory");
        state->rep_sequence = sequence;
    }
    return 0;
}

static DWORD WINAPI consumer(void *opaque)
{
    struct native_state *state = opaque;
    unsigned sequence;

    for (sequence = 1; sequence <= state->iterations; ++sequence) {
        uint32_t expected = sequence ^ 0xa5a55a5aU;
        uint32_t fill = sequence * 0x01010101U;
        unsigned index;

        while (state->unaligned.sequence != sequence) SwitchToThread();
        if (state->unaligned.payload != expected)
            InterlockedExchange(&state->failure, 1);
        state->unaligned.acknowledged = sequence;

        while (state->rep_sequence != sequence) SwitchToThread();
        for (index = 0; index < 64; ++index)
            if (state->rep_payload[index] != fill)
                InterlockedExchange(&state->failure, 2);
        state->rep_acknowledged = sequence;
    }
    return 0;
}

static int non_temporal_contract(void)
{
    __attribute__((aligned(16))) uint64_t output[2] = {0, 0};
    uint64_t expected = UINT64_C(0x1122334455667788);

    __asm__ volatile("movq %1, %%mm0\n\t"
                     "movntq %%mm0, %0\n\t"
                     "sfence\n\t"
                     "emms"
                     : "=m"(output[0]) : "m"(expected) : "memory");
    return output[0] == expected;
}

JNIEXPORT jlong JNICALL
Java_VkmtWindowsJavaMemoryModelProbe_nativeMemoryPrimitives(
    JNIEnv *environment, jclass type, jint iterations)
{
    struct native_state *state;
    HANDLE producer_thread, consumer_thread;

    (void)environment;
    (void)type;
    if (iterations <= 0) return 0;
    state = HeapAlloc(GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(*state));
    if (!state) return 0;
    state->iterations = (unsigned)iterations;
    producer_thread = CreateThread(NULL, 0, producer, state, 0, NULL);
    consumer_thread = CreateThread(NULL, 0, consumer, state, 0, NULL);
    if (!producer_thread || !consumer_thread) {
        if (producer_thread) CloseHandle(producer_thread);
        if (consumer_thread) CloseHandle(consumer_thread);
        HeapFree(GetProcessHeap(), 0, state);
        return 0;
    }
    WaitForSingleObject(producer_thread, INFINITE);
    WaitForSingleObject(consumer_thread, INFINITE);
    CloseHandle(producer_thread);
    CloseHandle(consumer_thread);
    if (state->failure ||
        state->unaligned.sequence != (uint32_t)iterations ||
        state->rep_sequence != (uint32_t)iterations ||
        !non_temporal_contract()) {
        HeapFree(GetProcessHeap(), 0, state);
        return 0;
    }
    HeapFree(GetProcessHeap(), 0, state);
    return ((jlong)0x4a34 << 48) | (uint32_t)iterations;
}
