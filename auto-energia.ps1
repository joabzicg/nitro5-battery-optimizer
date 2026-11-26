# Fica rodando em segundo plano (tarefa agendada no logon, como admin).
# Economia de energia do Windows LIGADA  -> modo economia (teto <= 15W)
# Economia de energia do Windows DESLIGADA -> modo desempenho maximo (110% na tomada)
# Log: %LOCALAPPDATA%\Energia\auto-energia.log

# Apps fechados ao entrar no modo economia (e na varredura automatica 30s apos o logon)
$AppsEconomia = 'steam', 'steamwebhelper', 'steamservice', 'EpicGamesLauncher',
                'EOSOverlayRenderer-Win64-Shipping', 'HWMonitor', 'Discord', 'DiscordSystemHelper',
                'tailscale-ipn', 'AMDRSServ', 'AMDRSSrcExt'

# Daemons silenciosos que acordam a GTX 1650 sozinhos: mantidos fechados automaticamente na bateria
$AppsSilenciososGpu = 'AMDRSServ', 'AMDRSSrcExt', 'NVIDIA Overlay', 'nvsphelper64', 'EOSOverlayRenderer-Win64-Shipping'

$logDir = Join-Path $env:LOCALAPPDATA 'Energia'
New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir 'auto-energia.log'
function Log($m) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" | Out-File -Append -Encoding utf8 $log }

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Energia {
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
  [DllImport("powrprof.dll")] static extern uint PowerSetUserConfiguredACPowerMode(ref Guid g);
  [DllImport("powrprof.dll")] static extern uint PowerSetUserConfiguredDCPowerMode(ref Guid g);
  [DllImport("powrprof.dll")] static extern uint PowerWriteACValueIndex(IntPtr root, ref Guid scheme, ref Guid sub, ref Guid setting, uint val);
  [DllImport("powrprof.dll")] static extern uint PowerWriteDCValueIndex(IntPtr root, ref Guid scheme, ref Guid sub, ref Guid setting, uint val);
  [DllImport("powrprof.dll")] static extern uint PowerReadACValueIndex(IntPtr root, ref Guid scheme, ref Guid sub, ref Guid setting, out uint val);
  [DllImport("powrprof.dll")] static extern uint PowerSetActiveScheme(IntPtr root, ref Guid scheme);
  [DllImport("powrprof.dll")] static extern uint PowerGetActiveScheme(IntPtr root, out IntPtr activeGuid);
  [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr hMem);
  [DllImport("nvapi64.dll", EntryPoint = "nvapi_QueryInterface", CallingConvention = CallingConvention.Cdecl)] static extern IntPtr NvQuery(uint id);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvInit();
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvUnload();
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvCreateSess(out IntPtr hS);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvDestroySess(IntPtr hS);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvLoad(IntPtr hS);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvSave(IntPtr hS);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvGetBase(IntPtr hS, out IntPtr hP);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvSetSet(IntPtr hS, IntPtr hP, byte[] s);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)] delegate int NvDelSet(IntPtr hS, IntPtr hP, uint id);

  static T NvGet<T>(uint id) where T : class {
    IntPtr p = NvQuery(id);
    return p == IntPtr.Zero ? null : Marshal.GetDelegateForFunctionPointer<T>(p);
  }
  static byte[] NvMakeDword(uint id, uint val) {
    const int SZ = 12320;
    byte[] b = new byte[SZ];
    BitConverter.GetBytes(0x00010000u | (uint)SZ).CopyTo(b, 0);
    BitConverter.GetBytes(id).CopyTo(b, 4100);
    BitConverter.GetBytes(0u).CopyTo(b, 4104);
    BitConverter.GetBytes(val).CopyTo(b, 8220);
    return b;
  }
  // Alterna o Perfil Global do Painel NVIDIA via nvapi64.dll DRS (nao acorda a GTX 1650!):
  //   integratedOnly=true  -> "Graficos integrados" (nenhum app novo/antigo acorda a GTX 1650 na bateria)
  //   integratedOnly=false -> "Selecao automatica"  (restaura 100% dos jogos na GTX 1650 na tomada)
  public static int SetNvidiaGlobalGpu(bool integratedOnly) {
    try {
      var init = NvGet<NvInit>(0x0150E828); var unload = NvGet<NvUnload>(0xD22BDD7E);
      var create = NvGet<NvCreateSess>(0x0694D52E); var destroy = NvGet<NvDestroySess>(0xDAD9CFF8);
      var load = NvGet<NvLoad>(0x375DBD6B); var save = NvGet<NvSave>(0xFCBC7E14);
      var getBase = NvGet<NvGetBase>(0xDA8466A0);
      var setSet = NvGet<NvSetSet>(0x577DD202); var delSet = NvGet<NvDelSet>(0xE4A26362);
      if (init == null || create == null || load == null || save == null || getBase == null) return -999;
      int st = init(); if (st != 0) return st;
      IntPtr hS; st = create(out hS); if (st != 0) { unload(); return st; }
      try {
        st = load(hS); if (st != 0) return st;
        IntPtr hP; st = getBase(hS, out hP); if (st != 0) return st;
        if (integratedOnly) {
          setSet(hS, hP, NvMakeDword(0x10F9DC80u, 0u)); // SHIM_MCCOMPAT_INTEGRATED
          setSet(hS, hP, NvMakeDword(0x10F9DC81u, 0u)); // SHIM_RENDERING_MODE_INTEGRATED
          setSet(hS, hP, NvMakeDword(0x10F9DC84u, 0u)); // SHIM_RENDERING_OPTIONS_DEFAULT
        } else {
          delSet(hS, hP, 0x10F9DC80u);
          delSet(hS, hP, 0x10F9DC81u);
          delSet(hS, hP, 0x10F9DC84u);
        }
        return save(hS);
      } finally { destroy(hS); unload(); }
    } catch { return -998; }
  }

  public static uint SetModo(Guid g) { return PowerSetUserConfiguredACPowerMode(ref g) | PowerSetUserConfiguredDCPowerMode(ref g); }
  public static uint WriteAC(Guid scheme, Guid sub, Guid setting, uint val) { return PowerWriteACValueIndex(IntPtr.Zero, ref scheme, ref sub, ref setting, val); }
  public static uint WriteDC(Guid scheme, Guid sub, Guid setting, uint val) { return PowerWriteDCValueIndex(IntPtr.Zero, ref scheme, ref sub, ref setting, val); }
  public static uint WriteBoth(Guid scheme, Guid sub, Guid setting, uint val) { return WriteAC(scheme, sub, setting, val) | WriteDC(scheme, sub, setting, val); }
  public static uint SetScheme(Guid scheme) { return PowerSetActiveScheme(IntPtr.Zero, ref scheme); }
  public static Guid GetActiveScheme() {
    IntPtr ptr;
    if (PowerGetActiveScheme(IntPtr.Zero, out ptr) != 0 || ptr == IntPtr.Zero) return Guid.Empty;
    try { return (Guid)Marshal.PtrToStructure(ptr, typeof(Guid)); }
    finally { LocalFree(ptr); }
  }
  public static int ReadAC(Guid scheme, Guid sub, Guid setting) {
    uint v;
    return PowerReadACValueIndex(IntPtr.Zero, ref scheme, ref sub, ref setting, out v) == 0 ? (int)v : -1;
  }
  public static int SetHz(int hz) {
    DEVMODE dm = new DEVMODE();
    dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
    if (!EnumDisplaySettings(null, -1, ref dm)) return -99;
    if (dm.dmDisplayFrequency == hz) return 0;
    dm.dmDisplayFrequency = hz;
    dm.dmFields = 0x400000;
    return ChangeDisplaySettings(ref dm, 1);
  }
}
"@

$OverlayEficiencia = [Guid]'961cc777-2547-4f9d-8174-7d86181b8a7a'
$OverlayDesempenho = [Guid]'ded574b5-45a0-4f42-8737-46345c09c238'

$PlanoEquilibrado    = [Guid]'381b4222-f694-41f0-9685-ff5bb260df2e'
$PlanoDesempenhoMax  = [Guid]'5970e164-64a9-4cc3-84b1-0bd6bf5e7657'
$PlanoAltoDesempenho = [Guid]'8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'

# Subgrupos e configuracoes (GUIDs nativos -> gravacao via powrprof.dll em ~5ms em vez de 15s de powercfg.exe!)
$SubProcessor       = [Guid]'54533251-82be-4824-96c1-47b60b740d00'
$SetProcMin         = [Guid]'893dee8e-2bef-41e0-89c6-b55d0929964c'
$SetProcMax         = [Guid]'bc5038f7-23e0-4960-96da-33abaf5935ec'
$SetBoostMode       = [Guid]'be337238-0d82-4146-a960-4f3749d470c7'
$SetFreqMax         = [Guid]'75b0ae3f-bce0-45a7-8c89-c9611c25e100'
$SetEpp             = [Guid]'36687f9e-e3a5-4dbf-b1dc-15eb381c6863'
$SetCoreParkMin     = [Guid]'0cc5b647-c1df-4637-891a-dec35c318583'
$SetPerfIncThresh   = [Guid]'06cadf0e-64ed-448a-8927-ce7bf90eb35d'
$SetPerfDecThresh   = [Guid]'12a0ab44-fe28-4fa9-b3bd-4b64f44960a6'
$SetPerfDecPol      = [Guid]'40fbefc7-2e9d-4d25-a185-0cfd8574bac6'

$SubVideo           = [Guid]'7516b95f-f776-4464-8c53-06167f40cc99'
$BrilhoPlano        = [Guid]'aded5e82-b909-4619-9949-f5d71dac0bcb'
$SetVideoIdle       = [Guid]'3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e'
$SetVideoDim        = [Guid]'17aaa29b-8b43-4b94-aafe-35f64daaf1ee'
$SubPciExpress      = [Guid]'501a4d13-42af-4429-9fd1-a8218c268e20'
$SetAspm            = [Guid]'ee12f906-d277-404b-b6da-e5fa1a576df5'
$SubAmdSlider       = [Guid]'c763b4ec-0e50-4b6b-9bed-2b92a6ee884e'; $SetAmdSlider    = [Guid]'7ec1751b-60ed-4588-afb5-9819d3d77d90'
$SubAmdPowerPlay    = [Guid]'f693fb01-e858-4f00-b20f-f30e12ac06d6'; $SetAmdPowerPlay = [Guid]'191f65b5-d45c-4a4f-8aae-1ab8bfd980e6'
$SubGraphics        = [Guid]'5fb4938d-1ee8-4b0f-9a3c-5036b0ab995c'; $SetGpuPref      = [Guid]'dd848b2a-8a5d-4451-9ae2-39cd41658f6c'
$SubSwitchable      = [Guid]'e276e160-7cb0-43c6-b20b-73f5dce39954'; $SetSwitchable   = [Guid]'a1662ab2-9d34-4e53-ba8b-2639b9e20857'
$SubEnergySaver     = [Guid]'de830923-a562-41af-a086-e3a2c6bad2da'; $SetEsThreshold  = [Guid]'e69653ca-cf7f-4f05-aa73-cb833fa90ad4'; $SetEsPolicy = [Guid]'5c5bb349-ad29-4ee2-9d0b-2b25270f7a81'
$SubJsTimer         = [Guid]'02f815b5-a5cf-4c84-bf20-649d1f75d3d8'; $SetJsTimer      = [Guid]'4c793e7d-a264-42e1-87d3-7a0d2f523ccd'
$SubMultimedia      = [Guid]'9596fb26-9850-41fd-ac3e-f7c3c00afd4b'; $SetVideoPlay    = [Guid]'34c7b99f-9a6d-4b3c-8dc7-b6693b78cef4'
$SubDisk            = [Guid]'0012ee47-9041-4b5d-9b77-535fba8b1442'
$SetAhciLpm         = [Guid]'0b2d69d7-a2a1-449c-9680-f91c70521c60'
$SetNvmeNoppme      = [Guid]'fc7372b6-ab2d-43ee-8797-15e9841f2cca'
$SetNvme1Idle       = [Guid]'d639518a-e56d-4345-8af2-b9f32fb26109'
$SetNvme2Idle       = [Guid]'d3d55efd-c1ff-424e-9dc3-441be7833010'
$SetNvme1Lat        = [Guid]'fc95af4d-40e7-4b6d-835a-56d131dbc80e'
$SetNvme2Lat        = [Guid]'dbc9e238-6de9-49e3-92cd-8c2b4946b472'
$RyzenAdj           = Join-Path $PSScriptRoot 'ryzenadj\ryzenadj.exe'

# Cache dos planos no inicio (evita disparar powercfg /list dezenas de vezes)
$PlanosCache = @()
function Refresh-Planos {
    $list = @(powercfg /list 2>$null | Select-String '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | ForEach-Object { [Guid]$_.Matches[0].Value })
    $script:PlanosCache = @($list + @($PlanoEquilibrado, $PlanoDesempenhoMax, $PlanoAltoDesempenho) | Select-Object -Unique)
}
Refresh-Planos
$TemDesempenhoMax = ($PlanosCache -contains $PlanoDesempenhoMax) -and ([Energia]::ReadAC($PlanoDesempenhoMax, $SubProcessor, $SetProcMax) -ge 0)

function Set-Todos([Guid]$sub, [Guid]$setting, [uint32]$value) {
    foreach ($p in $script:PlanosCache) { [void][Energia]::WriteBoth($p, $sub, $setting, $value) }
}
function Set-TodosDC([Guid]$sub, [Guid]$setting, [uint32]$value) {
    foreach ($p in $script:PlanosCache) { [void][Energia]::WriteDC($p, $sub, $setting, $value) }
}

function Set-RyzenSMU([ValidateSet('economia', 'desempenho')][string]$perfil) {
    if (-not (Test-Path $RyzenAdj)) { return }
    try {
        if ($perfil -eq 'economia') {
            # Ponto doce no SMU do Ryzen 5 4600H (~7.2W STAPM / ~8.1W Fast / ~7.2W APU Slow efetivos + SoC 14A para video 4K liso)
            # Media real na bateria: ~11-13W (~4h40-5h em 60Wh) | Teto <= 15W sem engasgar!
            & $RyzenAdj --stapm-limit=8000 --fast-limit=9000 --slow-limit=8000 --apu-slow-limit=8000 --vrm-current=22000 --vrmmax-current=30000 --vrmsoc-current=14000 --vrmsocmax-current=20000 --tctl-temp=68 --power-saving 2>$null | Out-Null
        } else {
            # Restaura TDP 110% na tomada (compensa escala ~0.9x do BIOS -> 45W STAPM / 54W Fast reais + max-performance)
            & $RyzenAdj --stapm-limit=50000 --fast-limit=60000 --slow-limit=50000 --apu-slow-limit=50000 --vrm-current=65000 --vrmmax-current=95000 --vrmsoc-current=22000 --vrmsocmax-current=32000 --tctl-temp=95 --max-performance 2>$null | Out-Null
        }
    } catch {}
    # Teste isolado (logman, provedores de audio) mostrou 0 glitches por escrita do ryzenadj, entao
    # NAO reinicia o audio aqui (isso so parava a musica a toa).
}

# Le o STAPM atual do SMU; $true se o teto de economia ainda esta aplicado (EC do NitroSense nao resetou).
function Test-SmuEconomia {
    try {
        $info = & $RyzenAdj -i 2>$null | Out-String
        if ($info -match 'STAPM LIMIT\s*\|\s*([\d.]+)') { return ([double]$Matches[1] -le 9.5) }
    } catch {}
    return $true   # sem leitura: nao mexe (evita escrever no SMU a toa)
}

function Set-NvidiaAuxHardware([ValidateSet('dormir', 'acordar')][string]$acao) {
    # Provado em teste A/B neste Nitro 5 AN515-44:
    # - GTX 1650 HABILITADA no PnP + driver nvlddmkm em Optimus D3 = ~12-13.8W totais (0W na dGPU!)
    # - GTX 1650 DESABILITADA no PnP = ~19.4W a 21W (+5.5W perdidos sem D3cold!)
    # Portanto garantimos que a GTX 1650 fique HABILITADA para dormir em D3, mas desligamos a Funcao 1
    # (NVIDIA HDMI Audio) e paramos o NvContainerLocalSystem (Overlay) para NADA acordar a placa na bateria.
    try {
        $gtx = Get-PnpDevice -Class Display -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'PCI\\VEN_10DE&DEV_1F99' }
        if ($gtx -and $gtx.Status -ne 'OK') {
            Enable-PnpDevice -InstanceId $gtx.InstanceId -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        }
        $nvAudio = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'PCI\\VEN_10DE&DEV_10FA' }
        if ($acao -eq 'dormir') {
            Stop-Service -Name 'NvContainerLocalSystem' -Force -ErrorAction SilentlyContinue
            Get-Process -Name 'NVIDIA Overlay','nvsphelper64','nvcontainer' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            if ($nvAudio -and $nvAudio.Status -eq 'OK') {
                Disable-PnpDevice -InstanceId $nvAudio.InstanceId -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            }
        } else {
            if ($nvAudio -and $nvAudio.Status -ne 'OK') {
                Enable-PnpDevice -InstanceId $nvAudio.InstanceId -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            }
            Start-Service -Name 'NvContainerLocalSystem' -ErrorAction SilentlyContinue
        }
    } catch {}
}

function Set-Brilho([byte]$pct, [switch]$SomenteReduzir) {
    if ($SomenteReduzir) {
        $atual = (Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness -ErrorAction SilentlyContinue).CurrentBrightness
        if ($null -ne $atual -and $atual -le $pct) { return }
    }
    Set-Todos $SubVideo $BrilhoPlano $pct
    Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods -ErrorAction SilentlyContinue |
        Invoke-CimMethod -MethodName WmiSetBrightness -Arguments @{ Timeout = [uint32]1; Brightness = $pct } | Out-Null
}
function Set-WallpaperEngine([ValidateSet('pause', 'play')][string]$acao) {
    $wp = Get-Process -Name 'wallpaper64', 'wallpaper32' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($wp -and $wp.Path) {
        try { & $wp.Path -control $acao 2>$null | Out-Null } catch {}
    }
}

function Aplicar-PlanoEconomia {
    $maxCpu = if (Test-Path $RyzenAdj) { 100 } else { 90 }
    Set-Todos $SubProcessor $SetProcMin 5
    Set-Todos $SubProcessor $SetProcMax $maxCpu
    Set-Todos $SubProcessor $SetBoostMode 0
    Set-Todos $SubProcessor $SetFreqMax 0
    Set-Todos $SubProcessor $SetEpp 75
    Set-Todos $SubProcessor $SetCoreParkMin 0
    Set-Todos $SubProcessor $SetPerfIncThresh 65
    Set-Todos $SubProcessor $SetPerfDecThresh 25
    Set-Todos $SubProcessor $SetPerfDecPol 1

    Set-Todos $SubAmdSlider    $SetAmdSlider    0    # 0 = Economia de bateria
    Set-Todos $SubAmdPowerPlay $SetAmdPowerPlay 0    # 0 = Otimizar bateria na iGPU Radeon
    Set-Todos $SubGraphics     $SetGpuPref      1    # 1 = Baixo consumo de energia (forca iGPU)
    Set-Todos $SubSwitchable   $SetSwitchable   0    # 0 = Forcar graficos redutores de energia
    Set-Todos $SubPciExpress   $SetAspm         2    # 2 = Maxima (se audio estalar, troque para 1 ou 0)
    Set-Todos $SubJsTimer      $SetJsTimer      1    # 1 = Desempenho maximo (evita engasgo/atraso em paginas web e WebSockets)
    Set-Todos $SubMultimedia   $SetVideoPlay    1    # 1 = Equilibrado (evita engasgos em video 4K)
    Set-Todos $SubDisk         $SetAhciLpm      2    # 2 = HIPM+DIPM
    Set-Todos $SubDisk         $SetNvmeNoppme   1    # 1 = NVMe NOPPME ligado
    Set-Todos $SubDisk         $SetNvme1Idle    100
    Set-Todos $SubDisk         $SetNvme2Idle    100
    Set-Todos $SubDisk         $SetNvme1Lat     50
    Set-Todos $SubDisk         $SetNvme2Lat     50
    Set-TodosDC $SubVideo       $SetVideoIdle   420  # 7 min para desligar a tela na bateria
    Set-TodosDC $SubVideo       $SetVideoDim    400  # esmaece 20s antes (6m40s)
    Set-TodosDC $SubEnergySaver $SetEsThreshold 100
    Set-TodosDC $SubEnergySaver $SetEsPolicy    1

    [void][Energia]::SetScheme($PlanoEquilibrado)
}

function Aplicar-PlanoDesempenho {
    Set-Todos $SubProcessor $SetProcMin 100
    Set-Todos $SubProcessor $SetProcMax 100
    Set-Todos $SubProcessor $SetBoostMode 2
    Set-Todos $SubProcessor $SetFreqMax 0
    Set-Todos $SubProcessor $SetEpp 0
    Set-Todos $SubProcessor $SetCoreParkMin 100
    Set-Todos $SubProcessor $SetPerfIncThresh 10
    Set-Todos $SubProcessor $SetPerfDecThresh 5
    Set-Todos $SubProcessor $SetPerfDecPol 0

    Set-Todos $SubAmdSlider    $SetAmdSlider    3    # 3 = O melhor desempenho
    Set-Todos $SubAmdPowerPlay $SetAmdPowerPlay 1    # 1 = Maximizar desempenho
    Set-Todos $SubGraphics     $SetGpuPref      0    # 0 = Nenhum (libera GTX 1650)
    Set-Todos $SubSwitchable   $SetSwitchable   3    # 3 = Maximizar desempenho
    Set-Todos $SubPciExpress   $SetAspm         0    # 0 = Desligado
    Set-Todos $SubJsTimer      $SetJsTimer      1    # 1 = Desempenho maximo
    Set-Todos $SubMultimedia   $SetVideoPlay    0    # 0 = Otimizar qualidade
    Set-Todos $SubDisk         $SetAhciLpm      0    # 0 = Active
    Set-Todos $SubDisk         $SetNvmeNoppme   0    # 0 = Desligado
    Set-Todos $SubDisk         $SetNvme1Idle    200
    Set-Todos $SubDisk         $SetNvme2Idle    2000
    Set-Todos $SubDisk         $SetNvme1Lat     0
    Set-Todos $SubDisk         $SetNvme2Lat     0
    # Mantem ESBATTTHRESHOLD=100 no perfil DC (so vale na bateria!)
    Set-TodosDC $SubVideo       $SetVideoIdle   420  # 7 min para desligar a tela na bateria
    Set-TodosDC $SubVideo       $SetVideoDim    400  # esmaece 20s antes (6m40s)
    Set-TodosDC $SubEnergySaver $SetEsThreshold 100
    Set-TodosDC $SubEnergySaver $SetEsPolicy    1

    $planoAC = if ($script:TemDesempenhoMax) { $PlanoDesempenhoMax } else { $PlanoAltoDesempenho }
    [void][Energia]::SetScheme($planoAC)
}

function Modo-Economia($motivo) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    # FASE INSTANTANEA (< 0.2s): plano nativo + SMU + NVIDIA Global iGPU + 60 Hz + overlay + brilho -> efeito imediato!
    Aplicar-PlanoEconomia
    Set-RyzenSMU 'economia'
    $nvDrs = [Energia]::SetNvidiaGlobalGpu($true)
    $o = [Energia]::SetModo($OverlayEficiencia)
    $hz = [Energia]::SetHz(60)
    Set-Brilho 20 -SomenteReduzir

    # FASE HARDWARE / BACKGROUND (logo em seguida, sem atrasar a resposta visual/SMU)
    Set-NvidiaAuxHardware 'dormir'
    Get-Process -Name $AppsEconomia -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Set-WallpaperEngine 'pause'
    Stop-Service Tailscale -ErrorAction SilentlyContinue
    Stop-Service vmcompute -ErrorAction SilentlyContinue
    wsl.exe --shutdown 2>$null | Out-Null

    $sw.Stop()
    Log "ECONOMIA   ($motivo; plano: Equilibrado, SMU: 8W, NV_DRS: $nvDrs, 60 Hz: $hz, modo: $o, $($sw.ElapsedMilliseconds)ms)"
}

function Modo-Desempenho($motivo) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    # FASE INSTANTANEA (< 0.2s): plano Ultimate Performance + SMU 50W/60W + NVIDIA Global Auto + 144 Hz + overlay + brilho!
    Aplicar-PlanoDesempenho
    Set-RyzenSMU 'desempenho'
    $nvDrs = [Energia]::SetNvidiaGlobalGpu($false)
    $o = [Energia]::SetModo($OverlayDesempenho)
    $hz = [Energia]::SetHz(144)
    Set-Brilho 100

    # FASE HARDWARE / BACKGROUND
    Set-NvidiaAuxHardware 'acordar'
    Set-WallpaperEngine 'play'
    Start-Service Tailscale -ErrorAction SilentlyContinue

    $sw.Stop()
    Log "DESEMPENHO ($motivo; plano: Desempenho Maximo, SMU: 50W/60W, NV_DRS: $nvDrs, 144 Hz: $hz, modo: $o, $($sw.ElapsedMilliseconds)ms)"
}

# Regras (vale o ultimo evento):
#   tirou da tomada                      -> economia (instantaneo < 0.5s!)
#   ligou na tomada                      -> desempenho (ou economia, se a Economia de energia estiver ligada)
#   acordou da suspensao / hibernacao    -> revalida modo + SMU imediatamente!
#   ligou a Economia de energia          -> economia
#   desligou a Economia de energia       -> desempenho, mesmo na bateria
$null = [Windows.System.Power.PowerManager, Windows.System.Power, ContentType = WindowsRuntime]
$PM = [Windows.System.Power.PowerManager]
Log 'iniciado'
$fonteAnt = $PM::PowerSupplyStatus
$esAnt = $PM::EnergySaverStatus -eq 'On'
$modo = if ($fonteAnt -eq 'NotPresent' -or $esAnt) { 'economia' } else { 'desempenho' }
if ($modo -eq 'economia') { Modo-Economia 'inicio' } else { Modo-Desempenho 'inicio' }

$ultimoSmu = [DateTime]::UtcNow
$ultimoTick = [DateTime]::UtcNow
$recheckNitroAt = [DateTime]::MinValue
# Varredura automatica 35s apos o logon: pega Steam/Epic/Discord/AMDRSServ que o Windows abre depois deste script
$varreduraPosBootAt = if ($modo -eq 'economia') { [DateTime]::UtcNow.AddSeconds(35) } else { [DateTime]::MinValue }

while ($true) {
    try {
        $agora = [DateTime]::UtcNow
        $gapSec = ($agora - $ultimoTick).TotalSeconds
        $ultimoTick = $agora

        $fonte = $PM::PowerSupplyStatus
        $es = $PM::EnergySaverStatus -eq 'On'
        $novo = $null; $motivo = $null

        # Detectou retorno de suspensao/hibernacao (salto de relogio > 8s num loop de 500ms)!
        if ($gapSec -gt 8) {
            $fonteAnt = $fonte
            $esAnt = $es
            $esperado = if ($fonte -eq 'NotPresent' -or $es) { 'economia' } else { 'desempenho' }
            Log "acordou da suspensao (gap=$([math]::Round($gapSec))s, fonte=$fonte) -> aplicando $esperado"
            if ($esperado -eq 'economia') { Modo-Economia 'retorno suspensao' } else { Modo-Desempenho 'retorno suspensao' }
            $modo = $esperado
            $ultimoSmu = $agora
            $recheckNitroAt = $agora.AddSeconds(6)
            Start-Sleep -Milliseconds 500
            continue
        }

        if ($fonte -ne $fonteAnt) {
            if ($fonte -eq 'NotPresent') { $novo = 'economia'; $motivo = 'saiu da tomada' }
            else { $novo = if ($es) { 'economia' } else { 'desempenho' }; $motivo = 'ligou na tomada' }
            $fonteAnt = $fonte
            # Sem Start-Sleep bloqueante! Troca AGORA (<0.5s) e agenda rechecagem anti-NitroSense em +6s
            $recheckNitroAt = $agora.AddSeconds(6)
        }
        elseif ($es -ne $esAnt) {
            $novo = if ($es) { 'economia' } else { 'desempenho' }
            $motivo = if ($es) { 'economia de energia ligada' } else { 'economia de energia desligada' }
        }
        $esAnt = $es

        if ($novo -and $novo -ne $modo) {
            if ($novo -eq 'economia') { Modo-Economia $motivo } else { Modo-Desempenho $motivo }
            $modo = $novo
            $ultimoSmu = $agora
        }
        # Varredura automatica pos-logon (35s): fecha Steam/Epic/Discord/AMDRSServ que o Windows abriu atrasado
        elseif ($varreduraPosBootAt -ne [DateTime]::MinValue -and $agora -ge $varreduraPosBootAt) {
            $varreduraPosBootAt = [DateTime]::MinValue
            if ($modo -eq 'economia') {
                Get-Process -Name $AppsEconomia -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                Set-NvidiaAuxHardware 'dormir'
                Set-WallpaperEngine 'pause'
                Log 'varredura pos-boot: apps de inicializacao fechados para liberar GTX 1650 D3'
            }
        }
        # Rechecagem anti-NitroSense 6s apos trocar tomada/suspensao (garante que o NitroSense nao desfez o plano)
        elseif ($recheckNitroAt -ne [DateTime]::MinValue -and $agora -ge $recheckNitroAt) {
            $recheckNitroAt = [DateTime]::MinValue
            if ($modo -eq 'economia') {
                Aplicar-PlanoEconomia
                if (-not (Test-SmuEconomia)) { Set-RyzenSMU 'economia' }
            } else {
                Aplicar-PlanoDesempenho
                Set-RyzenSMU 'desempenho'
            }
        }
        # A cada 60s: leitura leve para garantir que EC/NitroSense nao resetou SMU (economia) nem boost (tomada)
        elseif (($agora - $ultimoSmu).TotalSeconds -ge 60) {
            if ($modo -eq 'economia') {
                if (-not (Test-SmuEconomia)) {
                    Log 'teto SMU resetado pelo EC: reaplicando (8W)'
                    Set-RyzenSMU 'economia'
                }
                # Mantem daemons silenciosos de overlay/gravacao fora da bateria (sem fechar apps que voce abriu de proposito)
                Get-Process -Name $AppsSilenciososGpu -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
                if ((Get-Service -Name 'NvContainerLocalSystem' -ErrorAction SilentlyContinue).Status -eq 'Running') {
                    Set-NvidiaAuxHardware 'dormir'
                }
            } else {
                $ativo = [Energia]::GetActiveScheme()
                if ($ativo -ne [Guid]::Empty -and [Energia]::ReadAC($ativo, $SubProcessor, $SetBoostMode) -ne 2) {
                    Log 'NitroSense sobrescreveu plano AC (boost!=2): restaurando Desempenho Maximo'
                    Aplicar-PlanoDesempenho
                }
            }
            $ultimoSmu = $agora
        }
    } catch { Log "erro: $_" }
    Start-Sleep -Milliseconds 500
}
