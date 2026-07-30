import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;

public final class VkmtWindowsJavaMemoryModelProbe {
    private static final int PUBLICATIONS = 20000;
    private static final int ATOMIC_THREADS = 4;
    private static final int ATOMIC_ITERATIONS = 10000;

    private static volatile int publishedSequence;
    private static volatile int acknowledgedSequence;
    private static long publishedPayload;
    private static int publishedGuard;

    private static native long nativeMemoryPrimitives(int iterations);

    private static final class Node {
        final int value;
        final Node next;

        Node(int value, Node next) {
            this.value = value;
            this.next = next;
        }
    }

    private static long expectedPayload(int sequence) {
        return ((long)sequence << 32) ^
               (sequence * 0x9e3779b9L) ^ 0x13579bdf2468ace0L;
    }

    private static long publicationContract() throws Exception {
        publishedSequence = 0;
        acknowledgedSequence = 0;
        final AtomicReference<Throwable> failure =
            new AtomicReference<Throwable>();
        final long[] checksum = new long[1];
        Thread consumer = new Thread(new Runnable() {
            public void run() {
                long local = 0;
                try {
                    for (int sequence = 1; sequence <= PUBLICATIONS;
                         ++sequence) {
                        while (publishedSequence != sequence)
                            Thread.yield();
                        long payload = publishedPayload;
                        int guard = publishedGuard;
                        if (payload != expectedPayload(sequence) ||
                            guard != (sequence ^ 0x5a5a5a5a))
                            throw new AssertionError(
                                "publication mismatch " + sequence);
                        local ^= payload + guard;
                        acknowledgedSequence = sequence;
                    }
                    checksum[0] = local;
                } catch (Throwable throwable) {
                    failure.set(throwable);
                }
            }
        }, "vkmt-j4-publication-consumer");
        consumer.start();
        for (int sequence = 1; sequence <= PUBLICATIONS; ++sequence) {
            while (acknowledgedSequence != sequence - 1) Thread.yield();
            publishedPayload = expectedPayload(sequence);
            publishedGuard = sequence ^ 0x5a5a5a5a;
            publishedSequence = sequence;
        }
        consumer.join(120000);
        if (consumer.isAlive()) throw new AssertionError("publication deadlock");
        if (failure.get() != null) throw new AssertionError(failure.get());
        return checksum[0];
    }

    private static long monitorContract() throws Exception {
        final Object monitor = new Object();
        final int[] counter = new int[1];
        final boolean[] released = new boolean[1];
        Thread waiter = new Thread(new Runnable() {
            public void run() {
                synchronized (monitor) {
                    while (!released[0]) {
                        try {
                            monitor.wait();
                        } catch (InterruptedException exception) {
                            throw new RuntimeException(exception);
                        }
                    }
                }
            }
        }, "vkmt-j4-monitor-waiter");
        waiter.start();
        Thread[] workers = new Thread[4];
        for (int thread = 0; thread < workers.length; ++thread) {
            workers[thread] = new Thread(new Runnable() {
                public void run() {
                    for (int iteration = 0; iteration < 5000; ++iteration)
                        synchronized (monitor) {
                            counter[0]++;
                        }
                }
            }, "vkmt-j4-monitor-" + thread);
            workers[thread].start();
        }
        for (Thread worker : workers) {
            worker.join(120000);
            if (worker.isAlive())
                throw new AssertionError("monitor worker deadlock");
        }
        synchronized (monitor) {
            released[0] = true;
            monitor.notifyAll();
        }
        waiter.join(120000);
        if (waiter.isAlive() || counter[0] != 20000)
            throw new AssertionError("monitor result " + counter[0]);
        return counter[0];
    }

    private static long atomicContract() throws Exception {
        final AtomicInteger atomic32 = new AtomicInteger();
        final AtomicLong atomic64 = new AtomicLong();
        Thread[] workers = new Thread[ATOMIC_THREADS];
        for (int thread = 0; thread < workers.length; ++thread) {
            workers[thread] = new Thread(new Runnable() {
                public void run() {
                    for (int iteration = 0; iteration < ATOMIC_ITERATIONS;
                         ++iteration) {
                        int before32;
                        do {
                            before32 = atomic32.get();
                        } while (!atomic32.compareAndSet(before32,
                                                        before32 + 1));
                        long before64;
                        do {
                            before64 = atomic64.get();
                        } while (!atomic64.compareAndSet(before64,
                                                        before64 + 1));
                    }
                }
            }, "vkmt-j4-atomic-" + thread);
            workers[thread].start();
        }
        for (Thread worker : workers) {
            worker.join(120000);
            if (worker.isAlive())
                throw new AssertionError("atomic worker deadlock");
        }
        long expected = (long)ATOMIC_THREADS * ATOMIC_ITERATIONS;
        if (atomic32.get() != expected || atomic64.get() != expected)
            throw new AssertionError("atomic result " + atomic32 + " " +
                                     atomic64);
        return ((long)atomic32.get() << 32) | atomic64.get();
    }

    private static long queueAndOnceContract() throws Exception {
        final ConcurrentLinkedQueue<Integer> queue =
            new ConcurrentLinkedQueue<Integer>();
        final AtomicReference<String> once = new AtomicReference<String>();
        final AtomicInteger initialized = new AtomicInteger();
        final long[] sum = new long[1];
        Thread consumer = new Thread(new Runnable() {
            public void run() {
                long local = 0;
                int received = 0;
                while (received < PUBLICATIONS) {
                    Integer value = queue.poll();
                    if (value == null) {
                        Thread.yield();
                        continue;
                    }
                    local += value.intValue();
                    ++received;
                }
                sum[0] = local;
            }
        }, "vkmt-j4-queue-consumer");
        consumer.start();
        Thread[] producers = new Thread[4];
        for (int thread = 0; thread < producers.length; ++thread) {
            final int producer = thread;
            producers[thread] = new Thread(new Runnable() {
                public void run() {
                    if (once.compareAndSet(null, "VKMT_J4_ONCE_OK"))
                        initialized.incrementAndGet();
                    int start = producer * (PUBLICATIONS / 4);
                    int end = start + PUBLICATIONS / 4;
                    for (int value = start; value < end; ++value)
                        queue.offer(Integer.valueOf(value));
                }
            }, "vkmt-j4-queue-producer-" + thread);
            producers[thread].start();
        }
        for (Thread producer : producers) {
            producer.join(120000);
            if (producer.isAlive())
                throw new AssertionError("queue producer deadlock");
        }
        consumer.join(120000);
        long expected = (long)(PUBLICATIONS - 1) * PUBLICATIONS / 2;
        if (consumer.isAlive() || sum[0] != expected ||
            initialized.get() != 1 ||
            !"VKMT_J4_ONCE_OK".equals(once.get()))
            throw new AssertionError("queue/once result " + sum[0]);
        return sum[0] ^ initialized.get();
    }

    private static long gcBarrierContract() throws Exception {
        final Node[] roots = new Node[4];
        final AtomicInteger created = new AtomicInteger();
        final AtomicInteger activeMutators = new AtomicInteger();
        final CountDownLatch ready = new CountDownLatch(roots.length);
        final CountDownLatch start = new CountDownLatch(1);
        final AtomicReference<Throwable> failure =
            new AtomicReference<Throwable>();
        final long[] pressureChecksums = new long[roots.length];
        Thread[] mutators = new Thread[roots.length];
        for (int thread = 0; thread < mutators.length; ++thread) {
            final int slot = thread;
            mutators[thread] = new Thread(new Runnable() {
                public void run() {
                    activeMutators.incrementAndGet();
                    ready.countDown();
                    try {
                        start.await();
                        Node root = null;
                        byte[][] pressure = new byte[64][];
                        long pressureChecksum = 0;
                        for (int value = 0; value < 5000; ++value) {
                            root = new Node(value ^ slot, root);
                            roots[slot] = root;
                            int pressureSlot = value & 63;
                            pressure[pressureSlot] = new byte[512];
                            pressure[pressureSlot][0] = (byte)value;
                            pressureChecksum +=
                                pressure[pressureSlot][0] & 255;
                            created.incrementAndGet();
                            if ((value & 63) == 0) Thread.yield();
                        }
                        pressureChecksums[slot] = pressureChecksum;
                    } catch (Throwable throwable) {
                        failure.compareAndSet(null, throwable);
                    } finally {
                        activeMutators.decrementAndGet();
                    }
                }
            }, "vkmt-j4-mutator-" + thread);
            mutators[thread].start();
        }
        ready.await();
        start.countDown();
        for (Thread mutator : mutators) {
            mutator.join(120000);
            if (mutator.isAlive())
                throw new AssertionError("GC mutator deadlock");
        }
        System.out.println("VKMT_J4_GC_MUTATORS_JOINED created=" +
                           created.get());
        int seen = 0;
        long valueSum = 0;
        long pressureSum = 0;
        for (Node root : roots) {
            for (Node node = root; node != null; node = node.next) {
                ++seen;
                valueSum += node.value;
            }
        }
        for (long checksum : pressureChecksums) pressureSum += checksum;
        long expectedSum = 0;
        long expectedPressure = 0;
        for (int slot = 0; slot < roots.length; ++slot)
            for (int value = 0; value < 5000; ++value) {
                expectedSum += value ^ slot;
                expectedPressure += value & 255;
            }
        System.out.println("VKMT_J4_GC_TRAVERSAL_OK seen=" + seen +
                           " sum=" + valueSum + " pressure=" + pressureSum);
        if (failure.get() != null || activeMutators.get() != 0 ||
            created.get() != 20000 || seen != 20000 ||
            valueSum != expectedSum || pressureSum != expectedPressure)
            throw new AssertionError("GC barrier result " + created + "/" +
                                     seen + "/" + valueSum + "/" +
                                     pressureSum);
        return ((long)created.get() << 32) | seen ^ valueSum ^ pressureSum;
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 3)
            throw new IllegalArgumentException(
                "expected provider, mode, and rounds");
        if (!"32".equals(System.getProperty("sun.arch.data.model")) ||
            System.getProperty("java.vm.name").indexOf("Client") < 0)
            throw new AssertionError("wrong i386 Client VM");
        System.load(System.getProperty("vkmt.jni"));
        String mode = args[1];
        if (!"memory".equals(mode) && !"gc".equals(mode) &&
            !"combined".equals(mode))
            throw new IllegalArgumentException("unknown mode " + mode);
        int rounds = Integer.parseInt(args[2]);
        long total = 0;
        for (int round = 0; round < rounds; ++round) {
            long publication = 0;
            long monitor = 0;
            long atomic = 0;
            long queue = 0;
            long nativeMemory = 0;
            long gc = 0;
            if (!"gc".equals(mode)) {
                System.out.println("VKMT_J4_STAGE_BEGIN round=" + round +
                                   " stage=publication");
                publication = publicationContract();
                System.out.println("VKMT_J4_STAGE_OK round=" + round +
                                   " stage=publication");
                monitor = monitorContract();
                System.out.println("VKMT_J4_STAGE_OK round=" + round +
                                   " stage=monitor");
                atomic = atomicContract();
                System.out.println("VKMT_J4_STAGE_OK round=" + round +
                                   " stage=atomic");
                queue = queueAndOnceContract();
                System.out.println("VKMT_J4_STAGE_OK round=" + round +
                                   " stage=queue-once");
                nativeMemory = nativeMemoryPrimitives(20000);
                System.out.println("VKMT_J4_STAGE_OK round=" + round +
                                   " stage=native-memory");
                if (nativeMemory != 0x4a34000000004e20L)
                    throw new AssertionError("native memory result 0x" +
                                             Long.toHexString(nativeMemory));
            }
            if (!"memory".equals(mode)) {
                System.out.println("VKMT_J4_STAGE_BEGIN round=" + round +
                                   " stage=gc-barrier");
                gc = gcBarrierContract();
                System.out.println("VKMT_J4_STAGE_OK round=" + round +
                                   " stage=gc-barrier");
            }
            total ^= publication + monitor + atomic + queue + nativeMemory +
                     gc + round;
            System.out.println("VKMT_J4_ROUND_OK provider=" + args[0] +
                               " mode=" + mode +
                               " round=" + round +
                               " publication=" +
                               Long.toHexString(publication) +
                               " atomic=" + Long.toHexString(atomic) +
                               " native=" + Long.toHexString(nativeMemory));
        }
        System.out.println("VKMT_WINDOWS_JAVA_J4_OK provider=" + args[0] +
                           " mode=" + mode +
                           " rounds=" + rounds + " checksum=" +
                           Long.toHexString(total));
    }
}
