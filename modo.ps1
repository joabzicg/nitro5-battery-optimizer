#Requires -RunAsAdministrator
# Uso:  .\modo.ps1 bateria   (ao tirar da tomada)
#       .\modo.ps1 tomada    (ao ligar na tomada)
param([Parameter(Mandatory)][ValidateSet('bateria', 'tomada')][string]$Modo)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Tela {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
  public struct DEVMODE {
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
    public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
    public int dmFields, dmPositionX, dmPositionY, dmDisplayOrientation, dmDisplayFixedOutput;
    public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
    public short dmLogPixels;
    public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
    public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
  }
  [DllImport("user32.dll", CharSet = CharSet.Ansi)] static extern bool EnumDisplaySettings(string dev, int mode, ref DEVMODE dm);
  [DllImport("user32.dll", CharSet = CharSet.Ansi)] static extern int ChangeDisplaySettings(ref DEVMODE dm, int flags);
  public static int SetHz(int hz) {
    DEVMODE dm = new DEVMODE();
    dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
    if (!EnumDisplaySettings(null, -1, ref dm)) return -99;
    dm.dmDisplayFrequency = hz;
    dm.dmFields = 0x400000;               // DM_DISPLAYFREQUENCY
    return ChangeDisplaySettings(ref dm, 1); // CDS_UPDATEREGISTRY; 0 = sucesso
  }
}
"@

function Set-Brilho([byte]$pct) {
    Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods -ErrorAction SilentlyContinue |
        Invoke-CimMethod -MethodName WmiSetBrightness -Arguments @{ Timeout = [uint32]1; Brightness = $pct } | Out-Null
}

if ($Modo -eq 'bateria') {
    # Item 4: fecha o que segura a CPU e a GTX 1650 acordadas
    if (Get-Process steam -ErrorAction SilentlyContinue) { Start-Process 'steam://exit'; Start-Sleep 5 }
    $apps = 'steam', 'steamwebhelper', 'steamservice', 'EpicGamesLauncher', 'EOSOverlayRenderer-Win64-Shipping',
            'Discord', 'DiscordSystemHelper', 'HWMonitor', 'tailscale-ipn'
    Get-Process -Name $apps -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Stop-Service Tailscale -ErrorAction SilentlyContinue
    wsl.exe --shutdown 2>$null | Out-Null
    Stop-Service vmcompute -ErrorAction SilentlyContinue

    # Item 3: 60 Hz e brilho 30%
    $r = [Tela]::SetHz(60); Write-Host "Tela 60 Hz: $(if ($r -eq 0) {'OK'} else {"falhou ($r)"})"
    Set-Brilho 30
    Write-Host 'Modo bateria aplicado.'
}
else {
    $r = [Tela]::SetHz(144); Write-Host "Tela 144 Hz: $(if ($r -eq 0) {'OK'} else {"falhou ($r)"})"
    Start-Service Tailscale -ErrorAction SilentlyContinue
    Write-Host 'Modo tomada aplicado. Steam/Discord ficam fechados ate voce abrir.'
}
Start-Sleep -Seconds 3
