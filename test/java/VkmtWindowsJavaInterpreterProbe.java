import java.io.BufferedReader;
import java.io.File;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.lang.reflect.Method;
import java.net.URL;
import java.net.URLClassLoader;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

public final class VkmtWindowsJavaInterpreterProbe {
    private static String readAll(InputStream stream) throws Exception {
        BufferedReader reader = new BufferedReader(
            new InputStreamReader(stream, "UTF-8"));
        StringBuilder result = new StringBuilder();
        String line;
        while ((line = reader.readLine()) != null) {
            result.append(line);
        }
        return result.toString();
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 3) {
            throw new IllegalArgumentException(
                "expected launch-mode, data-model, and VM-kind");
        }

        String launchMode = args[0];
        String expectedModel = args[1];
        String expectedVmKind = args[2];
        String model = System.getProperty("sun.arch.data.model");
        String vmName = System.getProperty("java.vm.name");
        String osArch = System.getProperty("os.arch");
        String version = System.getProperty("java.version");

        if (!expectedModel.equals(model)) {
            throw new AssertionError("data model " + model +
                                     ", expected " + expectedModel);
        }
        if (vmName == null || vmName.indexOf(expectedVmKind) < 0) {
            throw new AssertionError("VM name " + vmName +
                                     " lacks " + expectedVmKind);
        }
        if (!"classpath".equals(launchMode) && !"jar".equals(launchMode)) {
            throw new AssertionError("unexpected launch mode " + launchMode);
        }

        String jarPath = System.getProperty("vkmt.probe.jar");
        if (jarPath == null) {
            throw new AssertionError("vkmt.probe.jar is unset");
        }

        String zipPayload;
        ZipFile zip = new ZipFile(jarPath);
        try {
            ZipEntry entry = zip.getEntry("vkmt/payload.txt");
            if (entry == null) {
                throw new AssertionError("missing ZIP payload");
            }
            zipPayload = readAll(zip.getInputStream(entry));
        } finally {
            zip.close();
        }
        if (!"VKMT_J1_ZIP_OK".equals(zipPayload)) {
            throw new AssertionError("wrong ZIP payload " + zipPayload);
        }

        URL jarUrl = new File(jarPath).toURI().toURL();
        URLClassLoader loader = new URLClassLoader(new URL[] {jarUrl}, null);
        String dynamicValue;
        try {
            Class<?> dynamicClass = Class.forName(
                "vkmt.dynamic.DynamicPayload", true, loader);
            Object instance = dynamicClass.newInstance();
            Method value = dynamicClass.getMethod("value");
            dynamicValue = (String)value.invoke(instance);
        } finally {
            loader.close();
        }
        if (!"VKMT_J1_REFLECTION_OK".equals(dynamicValue)) {
            throw new AssertionError("wrong reflection value " + dynamicValue);
        }

        System.out.println(
            "VKMT_WINDOWS_JAVA_J1_OK" +
            " mode=" + launchMode +
            " model=" + model +
            " vm=" + vmName +
            " os.arch=" + osArch +
            " version=" + version +
            " dynamic=" + dynamicValue +
            " zip=" + zipPayload);
    }
}
