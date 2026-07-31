#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DEFAULT_ROUNDS 1000000L
#define COMPILER_BARRIER() __asm__ __volatile__("" ::: "memory")

struct shared_word
{
    volatile LONG value;
    char padding[60];
} __attribute__((aligned(64)));

struct store_buffering_state
{
    struct shared_word x;
    struct shared_word y;
    struct shared_word start;
    struct shared_word done;
    struct shared_word stop;
    struct shared_word result[2];
};

struct worker_args
{
    struct store_buffering_state *state;
    LONG index;
};

static LONG atomic_read(volatile LONG *value)
{
    return InterlockedCompareExchange(value, 0, 0);
}

static DWORD WINAPI store_buffering_worker(void *opaque)
{
    struct worker_args *args = opaque;
    struct store_buffering_state *state = args->state;
    LONG observed = 0;

    for (;;)
    {
        LONG iteration;
        do
        {
            if (atomic_read(&state->stop.value)) return 0;
            iteration = atomic_read(&state->start.value);
            if (iteration == observed) SwitchToThread();
        } while (iteration == observed);
        observed = iteration;

        COMPILER_BARRIER();
        if (args->index == 0)
        {
            state->x.value = 1;
            COMPILER_BARRIER();
            state->result[0].value = state->y.value;
        }
        else
        {
            state->y.value = 1;
            COMPILER_BARRIER();
            state->result[1].value = state->x.value;
        }
        COMPILER_BARRIER();
        InterlockedIncrement(&state->done.value);
    }
}

int main(int argc, char **argv)
{
    struct store_buffering_state state;
    struct worker_args args[2];
    HANDLE threads[2];
    LONG rounds = DEFAULT_ROUNDS;
    LONG forbidden = 0;
    LONG first_forbidden = 0;
    LONG iteration;

    if (argc == 2)
    {
        char *end = NULL;
        long parsed = strtol(argv[1], &end, 10);
        if (!end || *end || parsed < 1 || parsed > 10000000L)
        {
            fprintf(stderr, "usage: %s [rounds:1..10000000]\n", argv[0]);
            return 2;
        }
        rounds = (LONG)parsed;
    }

    memset(&state, 0, sizeof(state));
    args[0].state = &state;
    args[0].index = 0;
    args[1].state = &state;
    args[1].index = 1;
    threads[0] = CreateThread(NULL, 0, store_buffering_worker, &args[0], 0, NULL);
    threads[1] = CreateThread(NULL, 0, store_buffering_worker, &args[1], 0, NULL);
    if (!threads[0] || !threads[1])
    {
        fprintf(stderr, "NO_TSO_PHASE2_FAIL test=store_buffering detail=CreateThread winerr=%lu\n",
                GetLastError());
        return 1;
    }

    for (iteration = 1; iteration <= rounds; ++iteration)
    {
        LONG target = iteration * 2;
        state.x.value = 0;
        state.y.value = 0;
        state.result[0].value = -1;
        state.result[1].value = -1;
        COMPILER_BARRIER();
        InterlockedExchange(&state.start.value, iteration);

        while (atomic_read(&state.done.value) != target) SwitchToThread();
        COMPILER_BARRIER();
        if (state.result[0].value == 0 && state.result[1].value == 0)
        {
            if (!first_forbidden) first_forbidden = iteration;
            if (++forbidden == 100) break;
        }
    }

    InterlockedExchange(&state.stop.value, 1);
    InterlockedIncrement(&state.start.value);
    WaitForMultipleObjects(2, threads, TRUE, 10000);
    CloseHandle(threads[0]);
    CloseHandle(threads[1]);

    if (forbidden)
    {
        fprintf(stderr,
                "NO_TSO_PHASE2_FAIL test=store_buffering rounds=%ld forbidden=%ld first=%ld\n",
                iteration, forbidden, first_forbidden);
        return 1;
    }

    printf("NO_TSO_PHASE2_STORE_BUFFERING_OK rounds=%ld forbidden=0\n", rounds);
    return 0;
}
