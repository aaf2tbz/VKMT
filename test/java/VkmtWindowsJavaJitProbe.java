import java.io.File;
import java.lang.management.CompilationMXBean;
import java.lang.management.ManagementFactory;
import java.lang.reflect.Method;
import java.net.URL;
import java.net.URLClassLoader;
import java.util.ArrayList;
import java.util.List;

public final class VkmtWindowsJavaJitProbe {
    private interface Operation {
        int apply(int value);
    }

    private static final class AddOperation implements Operation {
        public int apply(int value) {
            return value + 17;
        }
    }

    private static final class XorOperation implements Operation {
        public int apply(int value) {
            return value ^ 0x5a5a5a5a;
        }
    }

    private static native long nativeExecutableMemory(int iterations);

    private static int arithmetic(int value) {
        int result = value;
        for (int index = 0; index < 32; ++index)
            result = Integer.rotateLeft(result * 1664525 + 1013904223,
                                        (index & 7) + 1);
        return result;
    }

    private static long hotLoop(int seed, int iterations) {
        long checksum = 0;
        for (int index = 0; index < iterations; ++index)
            checksum += arithmetic(seed + index) & 0xffffffffL;
        return checksum;
    }

    private static int polymorphic(Operation operation, int value) {
        return operation.apply(value);
    }

    private static int implicitNull(Object[] values, int index) {
        Object value = values[index];
        if (value == null) throw new NullPointerException("compiled null");
        return value.hashCode();
    }

    private static int divide(int left, int right) {
        if (right == 0) throw new ArithmeticException("/ by zero");
        return left / right;
    }

    private static int recurse(int depth) {
        return depth == 0 ? 1 : 1 + recurse(depth - 1);
    }

    private static long warmExceptionSites(int iterations) {
        Object[] values = new Object[] {"VKMT_J3_NONNULL"};
        long checksum = 0;
        for (int index = 1; index <= iterations; ++index) {
            checksum += divide(index, 3);
            checksum += implicitNull(values, 0);
        }
        return checksum;
    }

    private static String exceptionResume() {
        Object[] values = new Object[] {null};
        for (int index = 0; index < 8; ++index) {
            try {
                implicitNull(values, 0);
                throw new AssertionError("implicit null did not throw");
            } catch (NullPointerException expected) {
            }
            try {
                divide(index, 0);
                throw new AssertionError("divide did not throw");
            } catch (ArithmeticException expected) {
            }
        }
        try {
            recurse(1000000);
            throw new AssertionError("stack guard did not throw");
        } catch (StackOverflowError expected) {
        }
        if (arithmetic(7) != arithmetic(7))
            throw new AssertionError("compiled exception resume failed");
        return "VKMT_J3_EXCEPTIONS_OK";
    }

    private static long classLoaderWave(String jarPath, int wave,
                                        int iterations)
        throws Exception {
        URL url = new File(jarPath).toURI().toURL();
        List<URLClassLoader> loaders = new ArrayList<URLClassLoader>();
        long checksum = 0;
        for (int loaderIndex = 0; loaderIndex < 4; ++loaderIndex) {
            URLClassLoader loader = new URLClassLoader(new URL[] {url}, null);
            loaders.add(loader);
            Class<?> type = Class.forName(
                "vkmt.dynamic.JitPayload", true, loader);
            Method method = type.getMethod("compute", Integer.TYPE);
            for (int iteration = 0; iteration < iterations; ++iteration)
                checksum += ((Integer)method.invoke(
                    null, Integer.valueOf(iteration + wave))).intValue();
        }
        for (URLClassLoader loader : loaders) loader.close();
        loaders.clear();
        String cleanup = System.getProperty("vkmt.j3.cleanup", "both");
        if (!"finalization".equals(cleanup) && !"none".equals(cleanup)) {
            System.out.println("VKMT_J3_GC_BEGIN wave=" + wave);
            System.gc();
            System.out.println("VKMT_J3_GC_END wave=" + wave);
        }
        if (!"gc".equals(cleanup) && !"none".equals(cleanup)) {
            System.out.println("VKMT_J3_FINALIZATION_BEGIN wave=" + wave);
            System.runFinalization();
            System.out.println("VKMT_J3_FINALIZATION_END wave=" + wave);
        }
        return checksum;
    }

    private static long deoptAndRecompile(int iterations) {
        Operation add = new AddOperation();
        Operation xor = new XorOperation();
        long checksum = 0;
        for (int index = 0; index < iterations; ++index)
            checksum += polymorphic(add, index);
        for (int index = 0; index < iterations; ++index)
            checksum += polymorphic((index & 1) == 0 ? add : xor, index);
        for (int index = 0; index < iterations; ++index)
            checksum += polymorphic(add, index);
        return checksum;
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 3)
            throw new IllegalArgumentException("expected model VM-kind mode");
        String expectedModel = args[0];
        String expectedVm = args[1];
        String mode = args[2];
        String model = System.getProperty("sun.arch.data.model");
        String vmName = System.getProperty("java.vm.name");
        boolean forced = mode.indexOf("xcomp") >= 0;
        if (!expectedModel.equals(model) || vmName.indexOf(expectedVm) < 0)
            throw new AssertionError("wrong VM " + model + " " + vmName);

        System.load(System.getProperty("vkmt.jni"));
        long executableMemory = nativeExecutableMemory(128);
        long expectedExecutable = (128L << 32) | 128L;
        if (executableMemory != expectedExecutable)
            throw new AssertionError("executable memory result 0x" +
                                     Long.toHexString(executableMemory));
        System.out.println("VKMT_J3_EXECMEM_OK transitions=257 flushes=257 " +
                           "patches=128");

        int hotIterations = forced ? 200 : 20000;
        long first = hotLoop(0x1234, hotIterations);
        long second = hotLoop(0x1234, hotIterations);
        if (first != second)
            throw new AssertionError("compiled hot loop changed");
        System.out.println("VKMT_J3_HOT_OK checksum=" +
                           Long.toHexString(first));

        long deopt;
        if (forced) {
            deopt = hotLoop(0x2345, 100);
            System.out.println("VKMT_J3_XCOMP_CONTROL_OK checksum=" +
                               Long.toHexString(deopt));
        } else {
            deopt = deoptAndRecompile(10000);
        }
        System.out.println("VKMT_J3_DEOPT_OK mode=" +
                           (forced ? "tiered-covered" : "exercised") +
                           " checksum=" + Long.toHexString(deopt));

        String jarPath = System.getProperty("vkmt.probe.jar");
        long loaderChecksum = 0;
        for (int wave = 0; wave < 4; ++wave) {
            loaderChecksum += classLoaderWave(
                jarPath, wave, forced ? 5 : 300);
            System.out.println("VKMT_J3_CODECACHE_WAVE_OK wave=" + wave);
        }

        long exceptionWarmup = warmExceptionSites(forced ? 20 : 20000);
        System.out.println("VKMT_J3_EXCEPTION_WARMUP_OK checksum=" +
                           Long.toHexString(exceptionWarmup));
        String exceptions = forced ? "VKMT_J3_EXCEPTIONS_OK"
                                   : exceptionResume();
        CompilationMXBean compilation =
            ManagementFactory.getCompilationMXBean();
        if (compilation == null || !compilation.isCompilationTimeMonitoringSupported())
            throw new AssertionError("compilation telemetry unavailable");
        long compilationTime = compilation.getTotalCompilationTime();
        if (compilationTime <= 0)
            throw new AssertionError("no compilation time recorded");

        System.out.println("VKMT_WINDOWS_JAVA_J3_OK model=" + model +
                           " vm=" + vmName + " mode=" + mode +
                           " compilationTimeMs=" + compilationTime +
                           " loaderChecksum=" +
                           Long.toHexString(loaderChecksum) +
                           " exceptions=" + exceptions);
    }
}
