import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.security.cert.X509Certificate;
import javax.net.ssl.HostnameVerifier;
import javax.net.ssl.HttpsURLConnection;
import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManager;
import javax.net.ssl.X509TrustManager;

public final class VkmtNativeJavaProbe {
    private static final long JNI_TOKEN = 0x564b4d544a4e4901L;

    private static native long nativeToken();

    private static void require(boolean condition, String message) {
        if (!condition) throw new IllegalStateException(message);
    }

    private static String fetchTls(String url) throws Exception {
        TrustManager[] trust = { new X509TrustManager() {
            public X509Certificate[] getAcceptedIssuers() {
                return new X509Certificate[0];
            }

            public void checkClientTrusted(X509Certificate[] chain, String authType) {
            }

            public void checkServerTrusted(X509Certificate[] chain, String authType) {
                require(chain != null && chain.length != 0, "TLS peer sent no certificate");
            }
        } };
        SSLContext context = SSLContext.getInstance("TLSv1.2");
        context.init(null, trust, new SecureRandom());

        HttpsURLConnection connection = (HttpsURLConnection)new URL(url).openConnection();
        connection.setSSLSocketFactory(context.getSocketFactory());
        connection.setHostnameVerifier((HostnameVerifier)(hostname, session) -> true);
        connection.setConnectTimeout(10000);
        connection.setReadTimeout(10000);

        ByteArrayOutputStream output = new ByteArrayOutputStream();
        InputStream response = connection.getInputStream();
        require(connection.getCipherSuite() != null, "TLS cipher suite missing");
        try (InputStream input = response) {
            byte[] buffer = new byte[4096];
            int count;
            while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
        }
        return new String(output.toByteArray(), StandardCharsets.UTF_8);
    }

    public static void main(String[] args) throws Exception {
        String vm = System.getProperty("java.vm.name");
        require(vm.contains("Server VM"), "not the Server VM: " + vm);
        require("aarch64".equals(System.getProperty("os.arch")), "not ARM64");

        System.load(System.getProperty("vkmt.jni"));
        require(nativeToken() == JNI_TOKEN, "JNI token mismatch");

        String response = fetchTls(System.getProperty("vkmt.tls.url"));
        require(response.contains("VKMT_TLS_SERVER_OK"), "TLS response marker missing");

        System.out.println("VKMT_NATIVE_JAVA_8U501_SERVER_CLASS_JNI_TLS_OK");
    }
}
