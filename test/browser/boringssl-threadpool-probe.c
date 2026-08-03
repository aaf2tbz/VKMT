#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <openssl/ec.h>
#include <openssl/ecdsa.h>
#include <openssl/nid.h>
#include <openssl/sha.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

struct verify_state
{
    EC_KEY *key;
    HANDLE done;
    const uint8_t *digest;
    const uint8_t *signature;
    unsigned signature_size;
    volatile LONG result;
};

static void verify_and_signal(struct verify_state *state)
{
    LONG result = ECDSA_verify(0, state->digest, SHA256_DIGEST_LENGTH,
                               state->signature, state->signature_size, state->key);
    InterlockedExchange(&state->result, result);
    MemoryBarrier();
    SetEvent(state->done);
}

static DWORD WINAPI queue_worker(void *opaque)
{
    verify_and_signal(opaque);
    return 0;
}

static void CALLBACK threadpool_worker(PTP_CALLBACK_INSTANCE instance, void *opaque, PTP_WORK work)
{
    (void)instance;
    (void)work;
    verify_and_signal(opaque);
}

static int wait_for_result(struct verify_state *state, const char *kind, int iteration)
{
    DWORD wait = WaitForSingleObject(state->done, 10000);
    if (wait != WAIT_OBJECT_0)
    {
        fprintf(stderr, "VKMT_BORINGSSL_THREADPOOL_WAIT_FAILED kind=%s iteration=%d wait=%#lx error=%lu\n",
                kind, iteration, (unsigned long)wait, (unsigned long)GetLastError());
        return 0;
    }
    MemoryBarrier();
    if (InterlockedCompareExchange(&state->result, 0, 0) != 1)
    {
        fprintf(stderr, "VKMT_BORINGSSL_THREADPOOL_VERIFY_FAILED kind=%s iteration=%d result=%ld\n",
                kind, iteration, (long)state->result);
        return 0;
    }
    return 1;
}

int main(void)
{
    static const char message[] = "VKMT Chromium threaded ECDSA completion gate";
    uint8_t digest[SHA256_DIGEST_LENGTH];
    uint8_t signature[256];
    unsigned signature_size = sizeof(signature);
    struct verify_state state;
    PTP_WORK work;
    EC_KEY *key;
    int iteration;

    SHA256((const uint8_t *)message, strlen(message), digest);
    key = EC_KEY_new_by_curve_name(NID_X9_62_prime256v1);
    if (!key || !EC_KEY_generate_key(key) ||
        !ECDSA_sign(0, digest, sizeof(digest), signature, &signature_size, key))
    {
        fputs("VKMT_BORINGSSL_THREADPOOL_SETUP_FAILED\n", stderr);
        if (key) EC_KEY_free(key);
        return 2;
    }

    state.key = key;
    state.done = CreateEventW(NULL, FALSE, FALSE, NULL);
    state.digest = digest;
    state.signature = signature;
    state.signature_size = signature_size;
    state.result = 0;
    if (!state.done)
    {
        EC_KEY_free(key);
        return 3;
    }

    for (iteration = 0; iteration != 1000; ++iteration)
    {
        state.result = 0;
        if (!QueueUserWorkItem(queue_worker, &state, WT_EXECUTEDEFAULT) ||
            !wait_for_result(&state, "QueueUserWorkItem", iteration))
        {
            CloseHandle(state.done);
            EC_KEY_free(key);
            return 4;
        }
    }

    work = CreateThreadpoolWork(threadpool_worker, &state, NULL);
    if (!work)
    {
        CloseHandle(state.done);
        EC_KEY_free(key);
        return 5;
    }
    for (iteration = 0; iteration != 1000; ++iteration)
    {
        state.result = 0;
        SubmitThreadpoolWork(work);
        if (!wait_for_result(&state, "CreateThreadpoolWork", iteration))
        {
            WaitForThreadpoolWorkCallbacks(work, TRUE);
            CloseThreadpoolWork(work);
            CloseHandle(state.done);
            EC_KEY_free(key);
            return 6;
        }
    }
    WaitForThreadpoolWorkCallbacks(work, FALSE);
    CloseThreadpoolWork(work);
    CloseHandle(state.done);
    EC_KEY_free(key);
    puts("VKMT_BORINGSSL_THREADPOOL_OK queue=1000 threadpool=1000 curve=P-256");
    return 0;
}
