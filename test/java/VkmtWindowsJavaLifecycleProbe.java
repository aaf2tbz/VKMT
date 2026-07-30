import java.util.concurrent.CountDownLatch;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;

public final class VkmtWindowsJavaLifecycleProbe {
    private static final int WORKERS = 4;
    private static final int CONTEXT_WORKERS = 1;
    private static final boolean SKIP_CONTEXT =
        Boolean.getBoolean("vkmt.j5.skipContext");
    private static final boolean SKIP_GC =
        Boolean.getBoolean("vkmt.j5.skipGC");
    private static final boolean SKIP_APC =
        Boolean.getBoolean("vkmt.j5.skipAPC");

    private static volatile boolean spin;
    private static volatile boolean gcDone;
    private static volatile int callbackReady = -1;
    private static volatile int callbackRelease = -1;
    private static volatile Object exceptionObject;
    private static volatile int exceptionDivisor = 1;
    private static volatile int exceptionSink;

    private static final AtomicInteger progress = new AtomicInteger();
    private static final AtomicInteger allocations = new AtomicInteger();
    private static final AtomicInteger callbacks = new AtomicInteger();
    private static final AtomicLong callbackChecksum = new AtomicLong();

    private static native void nativeRegisterWorker(int slot);
    private static native long nativeSuspendContextResume(int slot);
    private static native int nativeAttachCallback(int iteration);
    private static native int nativeApcRoundtrip();
    private static native void nativeClose();

    private static final class Node {
        final int value;
        final Node next;

        Node(int value, Node next) {
            this.value = value;
            this.next = next;
        }
    }

    private static int hotKernel(int seed) {
        int value = seed;
        for (int index = 0; index < 512; ++index)
            value = Integer.rotateLeft(value * 1664525 + 1013904223,
                                       index & 15) ^ index;
        return value;
    }

    private static int compiledExceptionContract(int iteration) {
        int caught = 0;
        try {
            Object value = exceptionObject;
            value.hashCode();
        } catch (NullPointerException expected) {
            caught |= 1;
        }
        try {
            int ignored = (iteration + 1) / exceptionDivisor;
            exceptionSink = ignored;
        } catch (ArithmeticException expected) {
            caught |= 2;
        }
        return caught;
    }

    public static void nativeCallback(int iteration, int tlsValue) {
        byte[][] pressure = new byte[32][];
        long checksum = tlsValue & 0xffffffffL;
        for (int index = 0; index < pressure.length; ++index) {
            pressure[index] = new byte[2048];
            pressure[index][0] = (byte)(iteration + index);
            checksum += pressure[index][0] & 255;
        }
        callbackChecksum.addAndGet(checksum);
        callbacks.incrementAndGet();
        callbackReady = iteration;
        long deadline = System.nanoTime() + 120000000000L;
        while (callbackRelease != iteration) {
            if (System.nanoTime() > deadline)
                throw new AssertionError("callback release timeout");
            Thread.yield();
        }
    }

    private static void awaitAtLeast(AtomicInteger value, int expected,
                                     String name) {
        long deadline = System.nanoTime() + 120000000000L;
        while (value.get() < expected) {
            if (System.nanoTime() > deadline)
                throw new AssertionError(name + " timeout " + value.get() +
                                         "/" + expected);
            Thread.yield();
        }
    }

    private static long lifecycleIteration(final int iteration,
                                           boolean runContextGate)
        throws Exception {
        System.out.println("VKMT_J5_PHASE iteration=" + iteration +
                           " phase=workers-start");
        final CountDownLatch ready = new CountDownLatch(WORKERS);
        final CountDownLatch start = new CountDownLatch(1);
        final AtomicReference<Throwable> failure =
            new AtomicReference<Throwable>();
        final Node[] roots = new Node[WORKERS];
        final int progressBase = progress.get();
        final int allocationBase = allocations.get();

        spin = true;
        gcDone = false;
        callbackReady = -1;
        callbackRelease = -1;

        Thread[] workers = new Thread[WORKERS];
        for (int thread = 0; thread < workers.length; ++thread) {
            final int slot = thread;
            workers[thread] = new Thread(new Runnable() {
                public void run() {
                    try {
                        nativeRegisterWorker(slot);
                        ready.countDown();
                        start.await();
                        int value = iteration ^ slot ^ 0x13579bdf;
                        while (spin) {
                            value = hotKernel(value);
                            progress.incrementAndGet();
                        }

                        Node root = null;
                        byte[][] pressure = new byte[64][];
                        int count = 0;
                        while (!gcDone) {
                            root = new Node(value ^ count, root);
                            if (count != 0 && (count & 511) == 0)
                                root = new Node(value ^ count, null);
                            roots[slot] = root;
                            int pressureSlot = count & 63;
                            pressure[pressureSlot] = new byte[1024];
                            pressure[pressureSlot][0] = (byte)count;
                            value = hotKernel(value + count);
                            allocations.incrementAndGet();
                            ++count;
                        }
                        if (root == null) throw new AssertionError("no root");
                    } catch (Throwable throwable) {
                        failure.compareAndSet(null, throwable);
                    }
                }
            }, "vkmt-j5-worker-" + iteration + "-" + thread);
            workers[thread].start();
        }

        if (!ready.await(120, java.util.concurrent.TimeUnit.SECONDS))
            throw new AssertionError("worker ready timeout");
        start.countDown();
        awaitAtLeast(progress, progressBase + WORKERS * 2, "compiled progress");
        System.out.println("VKMT_J5_PHASE iteration=" + iteration +
                           " phase=compiled-ready");

        long contextChecksum = 0;
        if (!SKIP_CONTEXT && runContextGate) {
            for (int slot = 0; slot < CONTEXT_WORKERS; ++slot) {
                long context = nativeSuspendContextResume(slot);
                if (context == 0)
                    throw new AssertionError("context roundtrip " + slot);
                contextChecksum ^= Long.rotateLeft(context, slot * 7);
            }
        }
        System.out.println("VKMT_J5_PHASE iteration=" + iteration +
                           " phase=context-complete");

        spin = false;
        awaitAtLeast(allocations, allocationBase + WORKERS * 4,
                     "allocation progress");
        System.out.println("VKMT_J5_PHASE iteration=" + iteration +
                           " phase=allocation-ready");

        final int callbackResult[] = new int[1];
        Thread callbackLauncher = new Thread(new Runnable() {
            public void run() {
                callbackResult[0] = nativeAttachCallback(iteration);
            }
        }, "vkmt-j5-callback-launcher-" + iteration);
        callbackLauncher.start();

        long callbackDeadline = System.nanoTime() + 120000000000L;
        while (callbackReady != iteration) {
            if (System.nanoTime() > callbackDeadline)
                throw new AssertionError("callback attach timeout");
            Thread.yield();
        }
        System.out.println("VKMT_J5_PHASE iteration=" + iteration +
                           " phase=callback-attached");

        if (!SKIP_GC) {
            System.gc();
            System.gc();
        }
        System.out.println("VKMT_J5_PHASE iteration=" + iteration +
                           " phase=gc-complete");
        callbackRelease = iteration;
        callbackLauncher.join(120000);
        if (callbackLauncher.isAlive() || callbackResult[0] != 1)
            throw new AssertionError("JNI attach/detach callback");
        System.out.println("VKMT_J5_PHASE iteration=" + iteration +
                           " phase=callback-detached");

        gcDone = true;
        for (Thread worker : workers) {
            worker.join(120000);
            if (worker.isAlive())
                throw new AssertionError("worker exit timeout");
        }
        if (failure.get() != null) throw new AssertionError(failure.get());
        System.out.println("VKMT_J5_PHASE iteration=" + iteration +
                           " phase=workers-joined");

        int seen = 0;
        long rootChecksum = 0;
        for (Node root : roots) {
            for (Node node = root; node != null; node = node.next) {
                ++seen;
                rootChecksum += node.value;
            }
        }
        int apc = SKIP_APC ? 1 : nativeApcRoundtrip();
        System.out.println("VKMT_J5_PHASE iteration=" + iteration +
                           " phase=apc-complete");
        int exceptions = compiledExceptionContract(iteration);
        if (seen < WORKERS || apc != 1 || exceptions != 3)
            throw new AssertionError("post-GC lifecycle result seen=" + seen +
                                     " apc=" + apc + " exceptions=" +
                                     exceptions);

        return contextChecksum ^ rootChecksum ^ seen ^
               allocations.get() ^ progress.get();
    }

    public static void main(String[] args) throws Exception {
        if (args.length < 2 || args.length > 3)
            throw new IllegalArgumentException(
                "expected launch, cycles, and optional exception-only");
        if (!"32".equals(System.getProperty("sun.arch.data.model")) ||
            System.getProperty("java.vm.name").indexOf("Client") < 0)
            throw new AssertionError("wrong i386 Client VM");
        System.load(System.getProperty("vkmt.jni"));

        int launch = Integer.parseInt(args[0]);
        int cycles = Integer.parseInt(args[1]);
        int warm = 0x2468ace0;
        for (int iteration = 0; iteration < 128; ++iteration)
            warm = hotKernel(warm + iteration);
        exceptionObject = new Object();
        exceptionDivisor = 1;
        for (int iteration = 0; iteration < 256; ++iteration)
            if (compiledExceptionContract(iteration) != 0)
                throw new AssertionError("exception warmup");
        exceptionObject = null;
        exceptionDivisor = 0;
        if (args.length == 3 && "exception-only".equals(args[2])) {
            for (int cycle = 0; cycle < cycles; ++cycle) {
                int exceptions = compiledExceptionContract(cycle);
                if (exceptions != 3)
                    throw new AssertionError("compiled exceptions=" +
                                             exceptions + " cycle=" + cycle);
            }
            nativeClose();
            System.out.println("VKMT_J5_EXCEPTION_ONLY_OK cycles=" + cycles);
            return;
        }
        if (args.length == 3 && ("gc-exception".equals(args[2]) ||
                                "gc-null".equals(args[2]) ||
                                "gc-divide".equals(args[2]))) {
            int expected = 3;
            if ("gc-null".equals(args[2])) {
                exceptionDivisor = 1;
                expected = 1;
            } else if ("gc-divide".equals(args[2])) {
                exceptionObject = new Object();
                expected = 2;
            }
            for (int cycle = 0; cycle < cycles; ++cycle) {
                System.gc();
                int exceptions = compiledExceptionContract(cycle);
                if (exceptions != expected)
                    throw new AssertionError("GC compiled exceptions=" +
                                             exceptions + " cycle=" + cycle);
            }
            nativeClose();
            System.out.println("VKMT_J5_GC_EXCEPTION_OK cycles=" + cycles);
            return;
        }

        long checksum = warm;
        for (int cycle = 0; cycle < cycles; ++cycle) {
            int iteration = launch * cycles + cycle;
            checksum ^= Long.rotateLeft(lifecycleIteration(
                                            iteration,
                                            launch == 0 && cycle == 0),
                                        cycle & 63);
            System.out.println("VKMT_J5_CYCLE_OK launch=" + launch +
                               " cycle=" + cycle + " callbacks=" +
                               callbacks.get());
        }
        if (callbacks.get() != cycles)
            throw new AssertionError("callback count " + callbacks.get());
        nativeClose();
        System.out.println("VKMT_WINDOWS_JAVA_J5_OK launch=" + launch +
                           " cycles=" + cycles + " callbacks=" +
                           callbacks.get() + " callbackChecksum=" +
                           Long.toHexString(callbackChecksum.get()) +
                           " checksum=" + Long.toHexString(checksum));
    }
}
