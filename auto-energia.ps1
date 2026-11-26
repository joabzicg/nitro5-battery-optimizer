# Fica rodando em segundo plano (tarefa agendada no logon, como admin).
# Economia de energia do Windows LIGADA  -> modo economia
# Economia de energia do Windows DESLIGADA -> modo desempenho maximo
# Log: %LOCALAPPDATA%\Energia\auto-energia.log

# Apps fechados ao entrar no modo economia (edite a lista se quiser)
$AppsEconomia = 'steam', 'steamwebhelper', 'steamservice', 'EpicGamesLauncher',
                'EOSOverlayRenderer-Win64-Shipping', 'HWMonitor', 'Discord', 'DiscordSystemHelper',
                'tailscale-ipn', 'AMDRSServ', 'AMDRSSrcExt'

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
  public static uint SetModo(Guid g) { return PowerSetUserConfiguredACPowerMode(ref g) | PowerSetUserConfiguredDCPowerMode(ref g); }
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

$PlanoEquilibrado    = '381b4222-f694-41f0-9685-ff5bb260df2e'
$PlanoDesempenhoMax  = '5970e164-64a9-4cc3-84b1-0bd6bf5e7657'
$PlanoAltoDesempenho = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'

# Subgrupos e configuracoes extras (AMD Ryzen 5 4600H + GTX 1650 Optimus)
$BrilhoPlano        = 'aded5e82-b909-4619-9949-f5d71dac0bcb'
$SubAmdSlider       = 'c763b4ec-0e50-4b6b-9bed-2b92a6ee884e'; $SetAmdSlider       = '7ec1751b-60ed-4588-afb5-9819d3d77d90'
$SubAmdPowerPlay    = 'f693fb01-e858-4f00-b20f-f30e12ac06d6'; $SetAmdPowerPlay    = '191f65b5-d45c-4a4f-8aae-1ab8bfd980e6'
$SubGraphics        = '5fb4938d-1ee8-4b0f-9a3c-5036b0ab995c'; $SetGpuPref         = 'dd848b2a-8a5d-4451-9ae2-39cd41658f6c'
$SubSwitchable      = 'e276e160-7cb0-43c6-b20b-73f5dce39954'; $SetSwitchable      = 'a1662ab2-9d34-4e53-ba8b-2639b9e20857'
$SubEnergySaver     = 'de830923-a562-41af-a086-e3a2c6bad2da'; $SetEsThreshold     = 'e69653ca-cf7f-4f05-aa73-cb833fa90ad4'; $SetEsPolicy = '5c5bb349-ad29-4ee2-9d0b-2b25270f7a81'
$SubJsTimer         = '02f815b5-a5cf-4c84-bf20-649d1f75d3d8'; $SetJsTimer         = '4c793e7d-a264-42e1-87d3-7a0d2f523ccd'
$SubMultimedia      = '9596fb26-9850-41fd-ac3e-f7c3c00afd4b'; $SetVideoPlay       = '34c7b99f-9a6d-4b3c-8dc7-b6693b78cef4'
$SubDisk            = '0012ee47-9041-4b5d-9b77-535fba8b1442'
$SetAhciLpm         = '0b2d69d7-a2a1-449c-9680-f91c70521c60'
$SetNvmeNoppme      = 'fc7372b6-ab2d-43ee-8797-15e9841f2cca'
$SetNvme1Idle       = 'd639518a-e56d-4345-8af2-b9f32fb26109'
$SetNvme2Idle       = 'd3d55efd-c1ff-424e-9dc3-441be7833010'
$SetNvme1Lat        = 'fc95af4d-40e7-4b6d-835a-56d131dbc80e'
$SetNvme2Lat        = 'dbc9e238-6de9-49e3-92cd-8c2b4946b472'
$SetCoreParkMin     = '0cc5b647-c1df-4637-891a-dec35c318583'
$SetPerfIncThresh   = '06cadf0e-64ed-448a-8927-ce7bf90eb35d'
$SetPerfDecThresh   = '12a0ab44-fe28-4fa9-b3bd-4b64f44960a6'
$SetPerfDecPol      = '40fbefc7-2e9d-4d25-a185-0cfd8574bac6'
$RyzenAdj           = Join-Path $PSScriptRoot 'ryzenadj\ryzenadj.exe'

function Set-RyzenSMU([ValidateSet('economia', 'desempenho')][string]$perfil) {
    if (-not (Test-Path $RyzenAdj)) { return }
    try {
        if ($perfil -eq 'economia') {
            # Ponto doce no SMU do Ryzen 5 4600H (~7.2W STAPM / ~8.1W Fast / ~7.2W APU Slow efetivos + SoC 14A para video 4K liso)
            # Media em uso normal: ~11-13W | Pico sob 100% CPU: ~14-14.8W (teto <= 15W sem engasgar!)
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
    # - GTX 1650 HABILITADA no PnP + driver nvlddmkm em Optimus D3 = ~13.8W totais (0W na dGPU!)
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

# O NitroSense troca o plano (Equilibrado <-> Alto desempenho) ao ligar/tirar da tomada,
# entao os valores vao para TODOS os planos, nao so para o ativo.
function Planos {
    $list = @(powercfg /list | Select-String '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' | ForEach-Object { $_.Matches[0].Value })
    ($list + @($PlanoEquilibrado, $PlanoDesempenhoMax, $PlanoAltoDesempenho)) | Select-Object -Unique
}
# Grava na tomada (AC) e na bateria (DC) de todos os planos: o modo vale nos dois.
function Set-Todos($sub, $setting, $value) {
    foreach ($p in Planos) {
        powercfg /setacvalueindex $p $sub $setting $value 2>$null | Out-Null
        powercfg /setdcvalueindex $p $sub $setting $value 2>$null | Out-Null
    }
}
function Set-TodosDC($sub, $setting, $value) {
    foreach ($p in Planos) {
        powercfg /setdcvalueindex $p $sub $setting $value 2>$null | Out-Null
    }
}
function Set-Brilho([byte]$pct, [switch]$SomenteReduzir) {
    if ($SomenteReduzir) {
        $atual = (Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightness -ErrorAction SilentlyContinue).CurrentBrightness
        if ($null -ne $atual -and $atual -le $pct) { return }
    }
    Set-Todos SUB_VIDEO $BrilhoPlano $pct
    Get-CimInstance -Namespace root/WMI -ClassName WmiMonitorBrightnessMethods -ErrorAction SilentlyContinue |
        Invoke-CimMethod -MethodName WmiSetBrightness -Arguments @{ Timeout = [uint32]1; Brightness = $pct } | Out-Null
}
function Set-WallpaperEngine([ValidateSet('pause', 'play')][string]$acao) {
    $wp = Get-Process -Name 'wallpaper64', 'wallpaper32' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($wp -and $wp.Path) {
        try { & $wp.Path -control $acao 2>$null | Out-Null } catch {}
    }
}

function Modo-Economia($motivo) {
    # 1. Hardware GTX 1650: para NVIDIA Overlay/Container e desliga Function 1 (HDMI Audio) para liberar D3/D3cold
    Set-NvidiaAuxHardware 'dormir'
    Get-Process -Name $AppsEconomia -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Stop-Service Tailscale -ErrorAction SilentlyContinue
    wsl.exe --shutdown 2>$null | Out-Null
    Stop-Service vmcompute -ErrorAction SilentlyContinue
    Set-WallpaperEngine 'pause'

    # 2. CPU: equilibrado + core parking total (0%) + boost desligado + EPP 95 + teto de 10W no SMU via RyzenAdj
    # Com RyzenAdj travando o pacote em 10W no hardware, manter PROCTHROTTLEMAX 100 (sem turbo) deixa cliques/abas
    # super fluidos ate 2,4-3,0 GHz dentro de 10W sem engasgar. Sem RyzenAdj, cai pro teto P1 (90%).
    $maxCpu = if (Test-Path $RyzenAdj) { 100 } else { 90 }
    Set-Todos SUB_PROCESSOR PROCTHROTTLEMIN 5
    Set-Todos SUB_PROCESSOR PROCTHROTTLEMAX $maxCpu
    Set-Todos SUB_PROCESSOR PERFBOOSTMODE 0
    Set-Todos SUB_PROCESSOR PROCFREQMAX 0
    Set-Todos SUB_PROCESSOR PERFEPP 75
    Set-Todos SUB_PROCESSOR $SetCoreParkMin 0
    Set-Todos SUB_PROCESSOR $SetPerfIncThresh 65
    Set-Todos SUB_PROCESSOR $SetPerfDecThresh 25
    Set-Todos SUB_PROCESSOR $SetPerfDecPol 1

    # 3. GPU / Plataforma / 2x NVMe: forca iGPU Radeon, AMD SMU/PowerPlay em economia,
    #    PCIe ASPM = 2 (Economia maxima -> coloca a GTX 1650 em D3), 2x NVMe em sono profundo PS4 (50ms/100ms).
    #    Wi-Fi fica em 0 para nao gerar estalos no audio. Se audio estalar com ASPM 2, troque para 1 ou 0.
    Set-Todos $SubAmdSlider    $SetAmdSlider    0    # 0 = Economia de bateria (reduz TDP/STAPM no SMU)
    Set-Todos $SubAmdPowerPlay $SetAmdPowerPlay 0    # 0 = Otimizar bateria na iGPU Radeon
    Set-Todos $SubGraphics     $SetGpuPref      1    # 1 = Baixo consumo de energia (forca iGPU)
    Set-Todos $SubSwitchable   $SetSwitchable   0    # 0 = Forcar graficos redutores de energia
    Set-Todos SUB_PCIEXPRESS   ASPM             2    # 2 = Maxima (se audio estalar, troque para 1 ou 0)
    Set-Todos $SubJsTimer      $SetJsTimer      0    # 0 = Economia de energia maxima no timer JS
    Set-Todos $SubMultimedia   $SetVideoPlay    1    # 1 = Equilibrado (evita engasgos em video 4K)
    Set-Todos $SubDisk         $SetAhciLpm      2    # 2 = HIPM+DIPM
    Set-Todos $SubDisk         $SetNvmeNoppme   1    # 1 = NVMe NOPPME ligado
    Set-Todos $SubDisk         $SetNvme1Idle    100  # 100 ms idle timeout NVMe primario
    Set-Todos $SubDisk         $SetNvme2Idle    100  # 100 ms idle timeout NVMe secundario
    Set-Todos $SubDisk         $SetNvme1Lat     50   # 50 ms latency tolerance -> habilita PS4 no NVMe 1
    Set-Todos $SubDisk         $SetNvme2Lat     50   # 50 ms latency tolerance -> habilita PS4 no NVMe 2
    Set-TodosDC $SubEnergySaver $SetEsThreshold 100  # Ativa Economia de Energia do Windows automaticamente na bateria
    Set-TodosDC $SubEnergySaver $SetEsPolicy    1    # 1 = Agressivo

    # Ativa o plano Equilibrado (em vez de ficar preso no Alto desempenho)
    powercfg /setactive $PlanoEquilibrado 2>$null | Out-Null
    powercfg /setactive SCHEME_CURRENT 2>$null | Out-Null

    # Aplica ponto doce no SMU (8W / 9W pico + SoC 14A + power-saving) -> fluido em 4K e teto total <= 15W
    Set-RyzenSMU 'economia'

    $o = [Energia]::SetModo($OverlayEficiencia)      # Melhor eficiencia energetica
    $hz = [Energia]::SetHz(60)
    Set-Brilho 20 -SomenteReduzir
    Log "ECONOMIA   ($motivo; plano: Equilibrado, SMU: 8W, 60 Hz: $hz, modo: $o)"
}

function Modo-Desempenho($motivo) {
    # Restaura hardware NVIDIA auxiliar + TDP 110% no SMU
    Set-NvidiaAuxHardware 'acordar'

    # CPU no talo (110%): minimo 100%, turbo agressivo (4.0 GHz), sem core parking, EPP 0, thresholds instantaneos
    Set-Todos SUB_PROCESSOR PROCTHROTTLEMIN 100
    Set-Todos SUB_PROCESSOR PROCTHROTTLEMAX 100
    Set-Todos SUB_PROCESSOR PERFBOOSTMODE 2
    Set-Todos SUB_PROCESSOR PROCFREQMAX 0
    Set-Todos SUB_PROCESSOR PERFEPP 0
    Set-Todos SUB_PROCESSOR $SetCoreParkMin 100
    Set-Todos SUB_PROCESSOR $SetPerfIncThresh 10
    Set-Todos SUB_PROCESSOR $SetPerfDecThresh 5
    Set-Todos SUB_PROCESSOR $SetPerfDecPol 0

    # GPU / Plataforma no maximo (libera GTX 1650 + SMU/PowerPlay/Switchable Graphics em maximo desempenho)
    Set-Todos $SubAmdSlider    $SetAmdSlider    3    # 3 = O melhor desempenho
    Set-Todos $SubAmdPowerPlay $SetAmdPowerPlay 1    # 1 = Maximizar desempenho
    Set-Todos $SubGraphics     $SetGpuPref      0    # 0 = Nenhum (libera GTX 1650)
    Set-Todos $SubSwitchable   $SetSwitchable   3    # 3 = Maximizar desempenho
    Set-Todos SUB_PCIEXPRESS   ASPM             0    # 0 = Desligado
    Set-Todos $SubJsTimer      $SetJsTimer      1    # 1 = Desempenho maximo
    Set-Todos $SubMultimedia   $SetVideoPlay    0    # 0 = Otimizar qualidade
    Set-Todos $SubDisk         $SetAhciLpm      0    # 0 = Active
    Set-Todos $SubDisk         $SetNvmeNoppme   0    # 0 = Desligado
    Set-Todos $SubDisk         $SetNvme1Idle    200
    Set-Todos $SubDisk         $SetNvme2Idle    2000
    Set-Todos $SubDisk         $SetNvme1Lat     0
    Set-Todos $SubDisk         $SetNvme2Lat     0
    # Mantem ESBATTTHRESHOLD=100 no perfil DC (so vale na bateria!): assim o Windows liga ES=On no segundo exato que tirar da tomada!
    Set-TodosDC $SubEnergySaver $SetEsThreshold 100
    Set-TodosDC $SubEnergySaver $SetEsPolicy    1

    # Ativa Desempenho Maximo (Ultimate Performance, que o NitroSense nao sobrescreve); fallback para Alto desempenho
    $planoAC = if ((powercfg /list | Out-String) -match $PlanoDesempenhoMax) { $PlanoDesempenhoMax } else { $PlanoAltoDesempenho }
    powercfg /setactive $planoAC 2>$null | Out-Null
    powercfg /setactive SCHEME_CURRENT 2>$null | Out-Null

    Set-RyzenSMU 'desempenho'

    $o = [Energia]::SetModo($OverlayDesempenho)      # Melhor desempenho
    $hz = [Energia]::SetHz(144)
    Set-Brilho 100
    Set-WallpaperEngine 'play'
    Start-Service Tailscale -ErrorAction SilentlyContinue
    Log "DESEMPENHO ($motivo; plano: Desempenho Maximo, SMU: 50W/60W, 144 Hz: $hz, modo: $o)"
}

# Regras (vale o ultimo evento):
#   tirou da tomada                      -> economia
#   ligou na tomada                      -> desempenho (ou economia, se a Economia de energia estiver ligada)
#   ligou a Economia de energia          -> economia
#   desligou a Economia de energia       -> desempenho, mesmo na bateria
$null = [Windows.System.Power.PowerManager, Windows.System.Power, ContentType = WindowsRuntime]
$PM = [Windows.System.Power.PowerManager]
Log 'iniciado'
$fonteAnt = $PM::PowerSupplyStatus
$esAnt = $PM::EnergySaverStatus -eq 'On'
$modo = if ($fonteAnt -eq 'NotPresent' -or $esAnt) { 'economia' } else { 'desempenho' }
if ($modo -eq 'economia') { Modo-Economia 'inicio' } else { Modo-Desempenho 'inicio' }

$ultimoSmu = Get-Date
while ($true) {
    try {
        $fonte = $PM::PowerSupplyStatus
        $es = $PM::EnergySaverStatus -eq 'On'
        $novo = $null; $motivo = $null
        if ($fonte -ne $fonteAnt) {
            Start-Sleep -Seconds 4   # deixa o NitroSense terminar de trocar o plano
            $es = $PM::EnergySaverStatus -eq 'On'
            if ($fonte -eq 'NotPresent') { $novo = 'economia'; $motivo = 'saiu da tomada' }
            else { $novo = if ($es) { 'economia' } else { 'desempenho' }; $motivo = 'ligou na tomada' }
            $fonteAnt = $fonte
        }
        elseif ($es -ne $esAnt) {
            $novo = if ($es) { 'economia' } else { 'desempenho' }
            $motivo = if ($es) { 'economia de energia ligada' } else { 'economia de energia desligada' }
        }
        $esAnt = $es
        if ($novo -and $novo -ne $modo) {
            if ($novo -eq 'economia') { Modo-Economia $motivo } else { Modo-Desempenho $motivo }
            $modo = $novo
            $ultimoSmu = Get-Date
        }
        # A cada 60s faz leitura (somente-leitura, 0 glitches de audio) para checar se o EC do NitroSense
        # resetou o teto SMU; so escreve no SMU se o EC realmente tiver resetado acima de 9.5W!
        elseif ($modo -eq 'economia' -and ((Get-Date) - $ultimoSmu).TotalSeconds -ge 60) {
            if (-not (Test-SmuEconomia)) {
                Log 'teto SMU resetado pelo EC: reaplicando (8W)'
                Set-RyzenSMU 'economia'
            }
            $ultimoSmu = Get-Date
        }
        # Na tomada: garante a cada 60s que o NitroSense nao reverteu o plano/boost para modo economia
        elseif ($modo -eq 'desempenho' -and ((Get-Date) - $ultimoSmu).TotalSeconds -ge 60) {
            $boostAc = powercfg /qh SCHEME_CURRENT SUB_PROCESSOR PERFBOOSTMODE 2>$null | Select-String 'Correntes Alternadas Atuais:\s+0x([0-9a-f]+)'
            if ($boostAc -and [Convert]::ToInt32($boostAc.Matches[0].Groups[1].Value, 16) -ne 2) {
                Log 'NitroSense sobrescreveu plano AC (boost!=2): restaurando Desempenho Maximo'
                Modo-Desempenho 'auto-heal AC'
            }
            $ultimoSmu = Get-Date
        }
    } catch { Log "erro: $_" }
    Start-Sleep -Seconds 3
}
