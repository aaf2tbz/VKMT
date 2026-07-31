/* Direct Rosetta synchronization probe. No Wine APIs are involved. */
#include <stdatomic.h>
#include <pthread.h>
#include <sched.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/sysctl.h>
#include <time.h>

#define ATOMIC_ROUNDS 1000000u
#define COND_ROUNDS 200000u

static _Atomic uint32_t sequence;
static uint32_t payload;
static _Atomic uint32_t failures;

static pthread_mutex_t ping_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t ping_cond = PTHREAD_COND_INITIALIZER;
static unsigned int ping_turn;

static void *atomic_producer(void *unused)
{
    uint32_t i;
    (void)unused;
    for (i = 1; i <= ATOMIC_ROUNDS; ++i)
    {
        while (atomic_load_explicit( &sequence, memory_order_acquire ) != 2 * (i - 1)) sched_yield();
        payload = i;
        atomic_store_explicit( &sequence, 2 * i - 1, memory_order_release );
    }
    return NULL;
}

static void *atomic_consumer(void *unused)
{
    uint32_t i;
    (void)unused;
    for (i = 1; i <= ATOMIC_ROUNDS; ++i)
    {
        while (atomic_load_explicit( &sequence, memory_order_acquire ) != 2 * i - 1) sched_yield();
        if (payload != i) atomic_fetch_add_explicit( &failures, 1, memory_order_relaxed );
        atomic_store_explicit( &sequence, 2 * i, memory_order_release );
    }
    return NULL;
}

static void *cond_ping(void *arg)
{
    unsigned int id = (unsigned int)(uintptr_t)arg;
    unsigned int i;
    for (i = 0; i < COND_ROUNDS; ++i)
    {
        pthread_mutex_lock( &ping_lock );
        while (ping_turn != id) pthread_cond_wait( &ping_cond, &ping_lock );
        ping_turn ^= 1;
        pthread_cond_signal( &ping_cond );
        pthread_mutex_unlock( &ping_lock );
    }
    return NULL;
}

int main(void)
{
    pthread_t producer, consumer, ping0, ping1;
    struct timespec start, end;
    int translated = 0;
    size_t size = sizeof(translated);

    if (sysctlbyname( "sysctl.proc_translated", &translated, &size, NULL, 0 )) translated = 0;
    clock_gettime( CLOCK_MONOTONIC, &start );

    if (pthread_create( &producer, NULL, atomic_producer, NULL ) ||
        pthread_create( &consumer, NULL, atomic_consumer, NULL )) return 2;
    pthread_join( producer, NULL );
    pthread_join( consumer, NULL );

    if (pthread_create( &ping0, NULL, cond_ping, (void *)(uintptr_t)0 ) ||
        pthread_create( &ping1, NULL, cond_ping, (void *)(uintptr_t)1 )) return 3;
    pthread_join( ping0, NULL );
    pthread_join( ping1, NULL );

    clock_gettime( CLOCK_MONOTONIC, &end );
    printf( "translated=%d atomic_rounds=%u cond_rounds=%u failures=%u elapsed_ms=%llu\n",
            translated, ATOMIC_ROUNDS, COND_ROUNDS,
            atomic_load_explicit( &failures, memory_order_relaxed ),
            (unsigned long long)(end.tv_sec - start.tv_sec) * 1000 +
            (end.tv_nsec - start.tv_nsec) / 1000000 );
    return failures ? 1 : 0;
}
