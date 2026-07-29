using System;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Xml;

internal static class ManagedRuntimeProbe
{
    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentProcessId();

    private static int workerValue;

    private static int Main(string[] args)
    {
        int expectedBits;
        if ((args.Length != 1 && args.Length != 2) ||
            !Int32.TryParse(args[0], out expectedBits))
            return 2;

        int actualBits = IntPtr.Size * 8;
        if (actualBits != expectedBits)
            return 3;

        Thread worker = new Thread(new ThreadStart(delegate { workerValue = 1120; }));
        worker.Start();
        worker.Join();
        if (workerValue != 1120)
            return 4;

        Assembly assembly = typeof(ManagedRuntimeProbe).Assembly;
        if (assembly.GetType("ManagedRuntimeProbe") == null)
            return 5;

        XmlDocument document = new XmlDocument();
        document.LoadXml("<vkmt><runtime version=\"11.2.0\"/></vkmt>");
        if (document.SelectSingleNode("/vkmt/runtime/@version").Value != "11.2.0")
            return 6;

        uint processId = GetCurrentProcessId();
        if (processId == 0)
            return 7;

        string architecture = args.Length == 2
            ? args[1]
            : (actualBits == 32 ? "I386" : "X86_64");
        Console.WriteLine("VKMT_WINE_MONO_11_2_0_{0}_OK PID={1}",
            architecture, processId);
        return 0;
    }
}
