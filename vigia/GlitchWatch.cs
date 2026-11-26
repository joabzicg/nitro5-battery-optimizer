using System;
using System.Runtime.InteropServices;
using System.Threading;

// Consumidor ETW em tempo real: conta os glitches do motor de audio do Windows
// (provedor Microsoft.Windows.Audio.KernelStreamingEndpoint, nivel 5 = evento "Glitch").
public static class GlitchWatch
{
    public static readonly Guid KseProvider = new Guid("553ca39b-c608-566d-18ae-7b9a03a39acd");
    static long _count;
    static long _total;
    public static int LastType = -1;
    public static long Take() { return Interlocked.Exchange(ref _count, 0); }
    public static long Total { get { return Interlocked.Read(ref _total); } }

    [StructLayout(LayoutKind.Sequential)]
    struct EVENT_TRACE_HEADER { public ushort Size; public ushort FieldTypeFlags; public uint Version; public uint ThreadId; public uint ProcessId; public long TimeStamp; public Guid Guid; public uint KernelTime; public uint UserTime; }
    [StructLayout(LayoutKind.Sequential)]
    struct EVENT_TRACE { public EVENT_TRACE_HEADER Header; public uint InstanceId; public uint ParentInstanceId; public Guid ParentGuid; public IntPtr MofData; public uint MofLength; public uint ClientContext; }
    [StructLayout(LayoutKind.Sequential)]
    struct SYSTEMTIME { public short a, b, c, d, e, f, g, h; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct TIME_ZONE_INFORMATION { public int Bias; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string StandardName; public SYSTEMTIME StandardDate; public int StandardBias; [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string DaylightName; public SYSTEMTIME DaylightDate; public int DaylightBias; }
    [StructLayout(LayoutKind.Sequential)]
    struct TRACE_LOGFILE_HEADER { public uint BufferSize; public uint Version; public uint ProviderVersion; public uint NumberOfProcessors; public long EndTime; public uint TimerResolution; public uint MaximumFileSize; public uint LogFileMode; public uint BuffersWritten; public Guid LogInstanceGuid; public IntPtr LoggerName; public IntPtr LogFileName; public TIME_ZONE_INFORMATION TimeZone; public long BootTime; public long PerfFreq; public long StartTime; public uint ReservedFlags; public uint BuffersLost; }
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate void EventRecordCallback(IntPtr record);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    delegate uint BufferCallback(IntPtr logfile);
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct EVENT_TRACE_LOGFILE { [MarshalAs(UnmanagedType.LPWStr)] public string LogFileName; [MarshalAs(UnmanagedType.LPWStr)] public string LoggerName; public long CurrentTime; public uint BuffersRead; public uint ProcessTraceMode; public EVENT_TRACE CurrentEvent; public TRACE_LOGFILE_HEADER LogfileHeader; public BufferCallback BufferCallback; public uint BufferSize; public uint Filled; public uint EventsLost; public EventRecordCallback EventRecordCallback; public uint IsKernelTrace; public IntPtr Context; }

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern ulong OpenTrace(ref EVENT_TRACE_LOGFILE logfile);
    [DllImport("advapi32.dll")] static extern int ProcessTrace(ulong[] handles, uint count, IntPtr start, IntPtr end);
    [DllImport("advapi32.dll")] static extern int CloseTrace(ulong handle);

    static EventRecordCallback _cb = OnEvent;
    static BufferCallback _bcb = b => 1;
    static ulong _handle;
    public static string Error = "";

    static void OnEvent(IntPtr rec)
    {
        // EVENT_HEADER: ProviderId @24, EventDescriptor @40 (Level @44); UserData ptr @96 no EVENT_RECORD
        byte[] g = new byte[16]; Marshal.Copy(rec + 24, g, 0, 16);
        if (new Guid(g) != KseProvider) return;
        if (Marshal.ReadByte(rec, 44) != 5) return;
        Interlocked.Increment(ref _count); Interlocked.Increment(ref _total);
        try { IntPtr ud = Marshal.ReadIntPtr(rec, 96); if (ud != IntPtr.Zero) LastType = Marshal.ReadInt32(ud, 16); } catch { }
    }

    public static bool Start(string session)
    {
        var lf = new EVENT_TRACE_LOGFILE();
        lf.LoggerName = session;
        lf.ProcessTraceMode = 0x00000100 | 0x10000000; // REAL_TIME | EVENT_RECORD
        lf.EventRecordCallback = _cb;
        lf.BufferCallback = _bcb;
        _handle = OpenTrace(ref lf);
        if (_handle == ulong.MaxValue || _handle == 0xFFFFFFFF) { Error = "OpenTrace falhou: " + Marshal.GetLastWin32Error(); return false; }
        var t = new Thread(() => { int r = ProcessTrace(new ulong[] { _handle }, 1, IntPtr.Zero, IntPtr.Zero); if (r != 0) Error = "ProcessTrace: " + r; });
        t.IsBackground = true; t.Start();
        return true;
    }
    public static void Stop() { if (_handle != 0) CloseTrace(_handle); }

    // Gerador de engasgo para teste: ocupa todos os nucleos em prioridade maxima por 'ms'.
    [DllImport("kernel32.dll")] static extern IntPtr GetCurrentThread();
    [DllImport("kernel32.dll")] static extern bool SetThreadPriority(IntPtr t, int p);
    public static void Hiccup(int ms)
    {
        int n = Environment.ProcessorCount; var ts = new Thread[n]; long until = DateTime.UtcNow.Ticks + ms * 10000L;
        for (int i = 0; i < n; i++) { ts[i] = new Thread(() => { SetThreadPriority(GetCurrentThread(), 15); while (DateTime.UtcNow.Ticks < until) { } }); ts[i].Start(); }
        foreach (var t in ts) t.Join();
    }
}
