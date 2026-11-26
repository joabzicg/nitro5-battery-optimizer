using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Threading;

// "Destravao": troca o formato da saida padrao (ex. 48k -> 44.1k) e volta ao original.
// Isso obriga o motor de audio a reabrir o canal com a placa (pin KS) sem matar os apps.
public static class SoftReset
{
    [ComImport, Guid("f8679f50-850a-41cf-9c72-430f290290c8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IPolicyConfig
    {
        [PreserveSig] int GetMixFormat([MarshalAs(UnmanagedType.LPWStr)] string id, out IntPtr fmt);
        [PreserveSig] int GetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id, bool bDefault, out IntPtr fmt);
        [PreserveSig] int ResetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id);
        [PreserveSig] int SetDeviceFormat([MarshalAs(UnmanagedType.LPWStr)] string id, IntPtr endpointFmt, IntPtr mixFmt);
    }
    [ComImport, Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9")] class PolicyConfigClient { }

    [ComImport, Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDeviceEnumerator { int EnumAudioEndpoints(int f, int s, out IntPtr c); [PreserveSig] int GetDefaultAudioEndpoint(int flow, int role, out IMMDevice d); }
    [ComImport, Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IMMDevice { [PreserveSig] int Activate(ref Guid iid, int ctx, IntPtr p, [MarshalAs(UnmanagedType.IUnknown)] out object o); int OpenPropertyStore(int a, out IntPtr p); [PreserveSig] int GetId([MarshalAs(UnmanagedType.LPWStr)] out string id); }
    [ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")] class MMDeviceEnumerator { }

    [ComImport, Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionManager2 { int GetAudioSessionControl(IntPtr a, int b, out IntPtr c); int GetSimpleAudioVolume(IntPtr a, int b, out IntPtr c); [PreserveSig] int GetSessionEnumerator(out IAudioSessionEnumerator e); }
    [ComImport, Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionEnumerator { [PreserveSig] int GetCount(out int n); [PreserveSig] int GetSession(int i, out IAudioSessionControl2 s); }
    [ComImport, Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IAudioSessionControl2
    {
        [PreserveSig] int GetState(out int state); int GetDisplayName(out IntPtr a); int SetDisplayName(string a, ref Guid g); int GetIconPath(out IntPtr a); int SetIconPath(string a, ref Guid g);
        int GetGroupingParam(out Guid g); int SetGroupingParam(ref Guid a, ref Guid g); int RegisterAudioSessionNotification(IntPtr a); int UnregisterAudioSessionNotification(IntPtr a);
        int GetSessionIdentifier(out IntPtr a); int GetSessionInstanceIdentifier(out IntPtr a); [PreserveSig] int GetProcessId(out uint pid);
    }

    public static string DefaultId()
    {
        var e = (IMMDeviceEnumerator)new MMDeviceEnumerator(); IMMDevice d; e.GetDefaultAudioEndpoint(0, 1, out d); string id; d.GetId(out id); return id;
    }

    // Lista "processo:estado" das sessoes de audio da saida padrao (estado 1 = tocando)
    public static string Sessions()
    {
        var e = (IMMDeviceEnumerator)new MMDeviceEnumerator(); IMMDevice d; e.GetDefaultAudioEndpoint(0, 1, out d);
        Guid iid = typeof(IAudioSessionManager2).GUID; object o; d.Activate(ref iid, 23, IntPtr.Zero, out o);
        var m = (IAudioSessionManager2)o; IAudioSessionEnumerator en; m.GetSessionEnumerator(out en); int n; en.GetCount(out n);
        var list = new List<string>();
        for (int i = 0; i < n; i++)
        {
            IAudioSessionControl2 s; en.GetSession(i, out s); int st; s.GetState(out st); uint pid; s.GetProcessId(out pid);
            string name = "?"; try { name = System.Diagnostics.Process.GetProcessById((int)pid).ProcessName; } catch { }
            if (pid != 0) list.Add(name + ":" + (st == 1 ? "tocando" : st == 0 ? "parado" : "expirado"));
        }
        return string.Join(", ", list);
    }

    static IntPtr Clone(IntPtr src, int rate)
    {
        int size = 18 + Marshal.ReadInt16(src, 16);
        IntPtr p = Marshal.AllocCoTaskMem(size); byte[] b = new byte[size]; Marshal.Copy(src, b, 0, size); Marshal.Copy(b, 0, p, size);
        int block = Marshal.ReadInt16(p, 12);
        Marshal.WriteInt32(p, 4, rate); Marshal.WriteInt32(p, 8, rate * block);
        return p;
    }

    public static string Run(string id)
    {
        var pc = (IPolicyConfig)new PolicyConfigClient();
        IntPtr dev, mix;
        int hr = pc.GetDeviceFormat(id, false, out dev); if (hr != 0) return "GetDeviceFormat 0x" + hr.ToString("X");
        hr = pc.GetMixFormat(id, out mix); if (hr != 0) return "GetMixFormat 0x" + hr.ToString("X");
        int rate = Marshal.ReadInt32(dev, 4);
        IntPtr devOrig = Clone(dev, rate), mixOrig = Clone(mix, rate);
        // tenta uma taxa alternativa aceita pela saida (Bluetooth costuma aceitar so uma)
        int used = 0; int h1 = 0;
        foreach (int alt in new[] { 44100, 48000, 96000, 32000 })
        {
            if (alt == rate) continue;
            h1 = pc.SetDeviceFormat(id, Clone(dev, alt), Clone(mix, alt));
            if (h1 == 0) { used = alt; break; }
        }
        if (used != 0) Thread.Sleep(150);
        int h2 = pc.SetDeviceFormat(id, devOrig, mixOrig);
        return used != 0
            ? string.Format("formato {0} -> {1} -> {0} (volta 0x{2:X})", rate, used, h2)
            : string.Format("formato {0} reaplicado (sem taxa alternativa; 0x{1:X})", rate, h2);
    }
}
