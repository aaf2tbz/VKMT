import java.io.BufferedReader;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.io.RandomAccessFile;
import java.lang.reflect.Method;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.URL;
import java.net.URLClassLoader;
import java.nio.ByteBuffer;
import java.nio.MappedByteBuffer;
import java.nio.channels.FileChannel;
import java.util.ArrayList;
import java.util.List;
import javax.net.ssl.HostnameVerifier;
import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLContext;
import javax.net.ssl.SSLSession;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;
import java.security.cert.X509Certificate;

public final class VkmtWindowsJavaServiceProbe {
    public interface Callback {
        long call();
    }

    private static native int nativePointerBits();
    private static native long nativeAddress();
    private static native long nativeRoundTrip(long value);
    private static native long nativeCallback(Callback callback);
    private static native boolean nativeCallbackException(Callback callback);
    private static native long nativeSecondThread(Callback callback);
    private static native long nativeQpcSleepMicros(int milliseconds);

    private static String readAll(InputStream stream) throws Exception {
        BufferedReader reader = new BufferedReader(
            new InputStreamReader(stream, "UTF-8"));
        StringBuilder result = new StringBuilder();
        String line;
        while ((line = reader.readLine()) != null) {
            result.append(line).append('\n');
        }
        return result.toString();
    }

    private static int recurse(int value) {
        return 1 + recurse(value + 1);
    }

    private static long allocationAndBuffers(File work) throws Exception {
        long checksum = 0;
        for (int cycle = 0; cycle < 4; ++cycle) {
            byte[][] blocks = new byte[16][];
            for (int index = 0; index < blocks.length; ++index) {
                blocks[index] = new byte[1024 * 1024];
                blocks[index][0] = (byte)(cycle + index);
                blocks[index][blocks[index].length - 1] =
                    (byte)(cycle ^ index);
                checksum += blocks[index][0] & 0xff;
                checksum += blocks[index][blocks[index].length - 1] & 0xff;
            }
            blocks = null;
            System.gc();
        }

        ByteBuffer direct = ByteBuffer.allocateDirect(4096);
        direct.putLong(0, 0x1122334455667788L);
        if (direct.getLong(0) != 0x1122334455667788L)
            throw new AssertionError("direct buffer mismatch");

        File mappedFile = new File(work, "mapped.bin");
        RandomAccessFile random = new RandomAccessFile(mappedFile, "rw");
        try {
            random.setLength(4096);
            MappedByteBuffer mapped = random.getChannel().map(
                FileChannel.MapMode.READ_WRITE, 0, 4096);
            mapped.putLong(128, 0x7766554433221100L);
            mapped.force();
            if (mapped.getLong(128) != 0x7766554433221100L)
                throw new AssertionError("mapped buffer mismatch");
        } finally {
            random.close();
        }
        /*
         * Windows keeps the section mapped until the MappedByteBuffer is
         * reclaimed.  The successful force/read above is the contract; defer
         * file removal until normal VM shutdown if it is still mapped here.
         */
        if (!mappedFile.delete()) mappedFile.deleteOnExit();
        return checksum;
    }

    private static int repeatedClassLoading(String jarPath) throws Exception {
        URL url = new File(jarPath).toURI().toURL();
        int count = 0;
        for (int index = 0; index < 32; ++index) {
            URLClassLoader loader = new URLClassLoader(new URL[] {url}, null);
            try {
                Class<?> type = Class.forName(
                    "vkmt.dynamic.DynamicPayload", true, loader);
                Object instance = type.newInstance();
                Method method = type.getMethod("value");
                if (!"VKMT_J1_REFLECTION_OK".equals(method.invoke(instance)))
                    throw new AssertionError("class-loader value mismatch");
                ++count;
            } finally {
                loader.close();
            }
        }
        System.gc();
        return count;
    }

    private static String javaThreadContract() throws Exception {
        final Object monitor = new Object();
        final ThreadLocal<String> local = new ThreadLocal<String>();
        final boolean[] ready = new boolean[1];
        final boolean[] release = new boolean[1];
        final String[] result = new String[1];

        Thread thread = new Thread(new Runnable() {
            public void run() {
                local.set("VKMT_J2_TLS_OK");
                synchronized (monitor) {
                    ready[0] = true;
                    monitor.notifyAll();
                    while (!release[0]) {
                        try {
                            monitor.wait();
                        } catch (InterruptedException exception) {
                            throw new RuntimeException(exception);
                        }
                    }
                    result[0] = local.get();
                }
            }
        }, "vkmt-j2-java-thread");
        thread.start();
        synchronized (monitor) {
            while (!ready[0]) monitor.wait();
            release[0] = true;
            monitor.notifyAll();
        }
        thread.join(30000);
        if (thread.isAlive()) throw new AssertionError("Java thread retained");
        return result[0];
    }

    private static String processBuilderContract(String javaExe,
                                                 String classPath)
        throws Exception {
        List<String> command = new ArrayList<String>();
        command.add(javaExe);
        command.add("-Xint");
        command.add("-cp");
        command.add(classPath);
        command.add("VkmtWindowsJavaServiceProbe");
        command.add("child");
        ProcessBuilder builder = new ProcessBuilder(command);
        builder.redirectErrorStream(true);
        builder.environment().put("VKMT_J2_CHILD", "VKMT_J2_CHILD_ENV_OK");
        Process child = builder.start();
        String output = readAll(child.getInputStream());
        int status = child.waitFor();
        if (status != 0 || output.indexOf("VKMT_J2_CHILD_OK") < 0)
            throw new AssertionError("child failed " + status + ": " + output);
        return "VKMT_J2_PROCESS_OK";
    }

    private static String socketContract() throws Exception {
        final ServerSocket server = new ServerSocket(
            0, 1, InetAddress.getByName("127.0.0.1"));
        final Throwable[] failure = new Throwable[1];
        Thread serverThread = new Thread(new Runnable() {
            public void run() {
                try {
                    Socket accepted = server.accept();
                    BufferedReader input = new BufferedReader(
                        new InputStreamReader(accepted.getInputStream(), "UTF-8"));
                    PrintWriter output = new PrintWriter(
                        new OutputStreamWriter(accepted.getOutputStream(), "UTF-8"),
                        true);
                    output.println("ECHO:" + input.readLine());
                    accepted.close();
                } catch (Throwable throwable) {
                    failure[0] = throwable;
                }
            }
        }, "vkmt-j2-socket-server");
        serverThread.start();

        Socket client = new Socket("127.0.0.1", server.getLocalPort());
        PrintWriter output = new PrintWriter(
            new OutputStreamWriter(client.getOutputStream(), "UTF-8"), true);
        BufferedReader input = new BufferedReader(
            new InputStreamReader(client.getInputStream(), "UTF-8"));
        output.println("VKMT_J2_SOCKET_TOKEN");
        String response = input.readLine();
        client.close();
        server.close();
        serverThread.join(30000);
        if (failure[0] != null) throw new AssertionError(failure[0]);
        if (!"ECHO:VKMT_J2_SOCKET_TOKEN".equals(response))
            throw new AssertionError("socket response " + response);
        return "VKMT_J2_SOCKET_OK";
    }

    private static String httpsContract(String url) throws Exception {
        TrustManager[] trustAll = new TrustManager[] {
            new X509TrustManager() {
                public X509Certificate[] getAcceptedIssuers() {
                    return new X509Certificate[0];
                }
                public void checkClientTrusted(X509Certificate[] chain,
                                               String authType) {
                }
                public void checkServerTrusted(X509Certificate[] chain,
                                               String authType) {
                }
            }
        };
        SSLContext context = SSLContext.getInstance("TLSv1.2");
        context.init(null, trustAll, null);
        HttpsURLConnection connection =
            (HttpsURLConnection)new URL(url).openConnection();
        connection.setSSLSocketFactory(context.getSocketFactory());
        connection.setHostnameVerifier(new HostnameVerifier() {
            public boolean verify(String host, SSLSession session) {
                return true;
            }
        });
        connection.setConnectTimeout(15000);
        connection.setReadTimeout(15000);
        String body = readAll(connection.getInputStream());
        connection.disconnect();
        if (body.indexOf("VKMT_J2_HTTPS_OK") < 0)
            throw new AssertionError("HTTPS payload missing");
        return "VKMT_J2_HTTPS_OK";
    }

    private static void installShutdownHook(final String path) {
        Runtime.getRuntime().addShutdownHook(new Thread(new Runnable() {
            public void run() {
                try {
                    FileOutputStream output = new FileOutputStream(path);
                    output.write("VKMT_J2_SHUTDOWN_HOOK_OK\n".getBytes("UTF-8"));
                    output.close();
                } catch (Exception exception) {
                    exception.printStackTrace();
                }
            }
        }, "vkmt-j2-shutdown-hook"));
    }

    public static void main(String[] args) throws Exception {
        if (args.length == 1 && "child".equals(args[0])) {
            if (!"VKMT_J2_CHILD_ENV_OK".equals(
                    System.getenv("VKMT_J2_CHILD")))
                throw new AssertionError("child environment missing");
            System.out.println("VKMT_J2_CHILD_OK");
            return;
        }
        if (args.length != 2)
            throw new IllegalArgumentException("expected model and VM kind");

        String expectedModel = args[0];
        String expectedVm = args[1];
        String model = System.getProperty("sun.arch.data.model");
        String vmName = System.getProperty("java.vm.name");
        if (!expectedModel.equals(model) ||
            vmName == null || vmName.indexOf(expectedVm) < 0)
            throw new AssertionError("wrong VM: " + model + " " + vmName);

        String jniPath = System.getProperty("vkmt.jni");
        String workPath = System.getProperty("vkmt.work");
        String jarPath = System.getProperty("vkmt.probe.jar");
        String javaExe = System.getProperty("vkmt.java.exe");
        String classPath = System.getProperty("vkmt.classpath");
        String httpsUrl = System.getProperty("vkmt.https.url");
        String hookPath = System.getProperty("vkmt.hook");
        System.load(jniPath);
        installShutdownHook(hookPath);

        int pointerBits = nativePointerBits();
        if (!expectedModel.equals(Integer.toString(pointerBits)))
            throw new AssertionError("JNI pointer width " + pointerBits);
        long address = nativeAddress();
        if (address == 0 ||
            (pointerBits == 32 && (address & 0xffffffff00000000L) != 0))
            throw new AssertionError("host pointer escaped: " +
                                     Long.toHexString(address));

        long roundTripInput = 0x1122334455667788L;
        long roundTrip = nativeRoundTrip(roundTripInput);
        if (roundTrip != (roundTripInput ^ 0x13579bdf2468ace0L))
            throw new AssertionError("JNI round trip mismatch");

        long callback = nativeCallback(new Callback() {
            public long call() {
                return 0x2233445566778899L;
            }
        });
        if (callback != 0x2233445566778899L)
            throw new AssertionError("JNI callback mismatch");
        long secondThread = nativeSecondThread(new Callback() {
            public long call() {
                return 0x33445566778899aaL;
            }
        });
        if (secondThread != 0x33445566778899aaL)
            throw new AssertionError("JNI attached thread mismatch");
        if (!nativeCallbackException(new Callback() {
                public long call() {
                    throw new IllegalStateException("VKMT_J2_JNI_EXCEPTION");
                }
            }))
            throw new AssertionError("JNI exception was not observed");

        File work = new File(workPath);
        if (!work.mkdirs() && !work.isDirectory())
            throw new AssertionError("cannot create work directory");
        long allocationChecksum = allocationAndBuffers(work);
        int classLoads = repeatedClassLoading(jarPath);
        String threadMarker = javaThreadContract();

        boolean javaException = false;
        try {
            throw new IllegalArgumentException("VKMT_J2_JAVA_EXCEPTION");
        } catch (IllegalArgumentException expected) {
            javaException = true;
        }
        boolean stackOverflow = false;
        try {
            recurse(0);
        } catch (StackOverflowError expected) {
            stackOverflow = true;
        }
        if (!javaException || !stackOverflow)
            throw new AssertionError("exception contract failed");

        String process = processBuilderContract(javaExe, classPath);
        String socket = socketContract();
        String https = httpsContract(httpsUrl);

        long qpcMicros = nativeQpcSleepMicros(25);
        long before = System.nanoTime();
        Thread.sleep(20);
        long javaMicros = (System.nanoTime() - before) / 1000L;
        if (qpcMicros < 10000 || qpcMicros > 2000000 ||
            javaMicros < 5000 || javaMicros > 2000000)
            throw new AssertionError("timer range " + qpcMicros +
                                     "/" + javaMicros);

        System.out.println(
            "VKMT_WINDOWS_JAVA_J2_OK" +
            " model=" + model +
            " vm=" + vmName +
            " pointerBits=" + pointerBits +
            " address=0x" + Long.toHexString(address) +
            " callback=0x" + Long.toHexString(callback) +
            " secondThread=0x" + Long.toHexString(secondThread) +
            " allocationChecksum=" + allocationChecksum +
            " classLoads=" + classLoads +
            " thread=" + threadMarker +
            " exceptions=VKMT_J2_EXCEPTIONS_OK" +
            " process=" + process +
            " socket=" + socket +
            " https=" + https +
            " qpcMicros=" + qpcMicros +
            " javaMicros=" + javaMicros);
    }
}
