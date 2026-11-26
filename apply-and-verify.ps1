$outLog = Join-Path $env:LOCALAPPDATA 'Energia\hardware-verify.log'
New-Item -ItemType Directory -Force (Split-Path $outLog) | Out-Null
"=== INICIO $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File -Encoding utf8 $outLog

# 1. Reinicia tarefa Energia Automatica com o novo auto-energia.ps1
Stop-ScheduledTask -TaskName 'Energia Automatica' -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'auto-energia\.ps1' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 500
Start-ScheduledTask -TaskName 'Energia Automatica'
Start-Sleep -Seconds 3

# 1b. Otimiza rede (Cloudflare DoH 17ms no Chrome/Edge com fallback automatico + Roaming Wi-Fi AX200 em Medio)
"=== REDE (DoH + WI-FI ROAMING) ===" | Out-File -Append -Encoding utf8 $outLog
try {
    foreach ($path in @('HKLM:\SOFTWARE\Policies\Google\Chrome', 'HKLM:\SOFTWARE\Policies\Microsoft\Edge')) {
        New-Item -Path $path -Force | Out-Null
        Set-ItemProperty -Path $path -Name 'DnsOverHttpsMode' -Value 'automatic' -Type String
        Set-ItemProperty -Path $path -Name 'DnsOverHttpsTemplates' -Value 'https://cloudflare-dns.com/dns-query' -Type String
    }
    "DoH Cloudflare (automatic): OK (Chrome + Edge)" | Out-File -Append -Encoding utf8 $outLog
} catch {
    "DoH err: $_" | Out-File -Append -Encoding utf8 $outLog
}
try {
    $curRoam = (Get-NetAdapterAdvancedProperty -Name 'Wi-Fi' -RegistryKeyword 'RoamAggressiveness' -EA SilentlyContinue).DisplayValue
    if ($curRoam -ne '3. Média') {
        Set-NetAdapterAdvancedProperty -Name 'Wi-Fi' -RegistryKeyword 'RoamAggressiveness' -DisplayValue '3. Média' -ErrorAction Stop
        "Wi-Fi RoamAggressiveness: $curRoam -> 3. Média (OK)" | Out-File -Append -Encoding utf8 $outLog
    } else {
        "Wi-Fi RoamAggressiveness: ja estava em 3. Média" | Out-File -Append -Encoding utf8 $outLog
    }
} catch {
    "Wi-Fi Roaming err: $_" | Out-File -Append -Encoding utf8 $outLog
}

# 2. Aplica RyzenAdj conforme a fonte (AC = 55W/65W 110% | Bateria = 7.2W/7.6W <=15W) e captura --info
$ra = Join-Path $PSScriptRoot 'ryzenadj\ryzenadj.exe'
$naTomada = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus -EA SilentlyContinue).PowerOnline
"=== RYZENADJ APPLY (PowerOnline=$naTomada) ===" | Out-File -Append -Encoding utf8 $outLog
if ($naTomada) {
    & $ra --stapm-limit=55000 --fast-limit=65000 --slow-limit=55000 --apu-slow-limit=55000 --vrm-current=70000 --vrmmax-current=100000 --vrmsoc-current=25000 --vrmsocmax-current=35000 --tctl-temp=95 --max-performance 2>&1 | Out-File -Append -Encoding utf8 $outLog
} else {
    & $ra --stapm-limit=7200 --fast-limit=7600 --slow-limit=7200 --apu-slow-limit=7200 --vrm-current=19000 --vrmmax-current=25000 --vrmsoc-current=14000 --vrmsocmax-current=20000 --tctl-temp=68 --power-saving 2>&1 | Out-File -Append -Encoding utf8 $outLog
}
Start-Sleep -Seconds 2
"=== RYZENADJ --INFO ===" | Out-File -Append -Encoding utf8 $outLog
& $ra --info 2>&1 | Out-File -Append -Encoding utf8 $outLog

# 3. Testa leitura do AcerGamingFunction (backlight teclado / perfil)
"=== ACER WMI ===" | Out-File -Append -Encoding utf8 $outLog
try {
    $ag = Get-CimInstance -Namespace root\WMI -ClassName AcerGamingFunction -ErrorAction Stop
    $kb = Invoke-CimMethod -InputObject $ag -MethodName GetGamingKBBacklight -ErrorAction SilentlyContinue
    "KBBacklight: $($kb | Out-String)" | Out-File -Append -Encoding utf8 $outLog
} catch {
    "AcerWMI err: $_" | Out-File -Append -Encoding utf8 $outLog
}

# 4. Aguarda 10s para GTX 1650 entrar em D3 e EC estabilizar, depois mede 3 amostras limpas
"=== VERIFICACAO DE CONSUMO (10s settle) ===" | Out-File -Append -Encoding utf8 $outLog
Start-Sleep -Seconds 10
$null = [Windows.System.Power.PowerManager, Windows.System.Power, ContentType = WindowsRuntime]
$nv = Get-PnpDevice -Class Display | Where-Object { $_.FriendlyName -match 'NVIDIA' } | Select-Object -First 1
$nvAudio = Get-PnpDevice | Where-Object { $_.InstanceId -match 'PCI\\VEN_10DE&DEV_10FA' } | Select-Object -First 1
"GTX1650 Status=$($nv.Status) | NV_Audio Status=$($nvAudio.Status) | NvContainer=$((Get-Service NvContainerLocalSystem -ErrorAction SilentlyContinue).Status) | HWMonitor_Running=$([bool](Get-Process HWMonitor -ErrorAction SilentlyContinue))" | Out-File -Append -Encoding utf8 $outLog

for ($i = 1; $i -le 3; $i++) {
    $b = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus
    $cpu = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation | Where-Object { $_.Name -eq '_Total' }
    $d = [BitConverter]::ToInt32((Get-PnpDeviceProperty -InstanceId $nv.InstanceId -KeyName 'DEVPKEY_Device_PowerData').Data, 4)
    $w = [math]::Round($b.DischargeRate / 1000.0, 2)
    $mhz = [math]::Round(3000 * ($cpu.PercentProcessorPerformance / 100.0))
    $hrs = if ($w -gt 0.5) { [math]::Round(60.0 / $w, 1) } else { 0 }
    "Sample ${i}: -${w} W (~${hrs}h em 60Wh) | CPU=$($cpu.PercentProcessorTime)% (~${mhz}MHz, C3:$($cpu.PercentC3Time)%) | GTX1650_D=$d | ES=$([Windows.System.Power.PowerManager]::EnergySaverStatus)" | Out-File -Append -Encoding utf8 $outLog
    if ($i -lt 3) { Start-Sleep -Seconds 4 }
}
"=== FIM ===" | Out-File -Append -Encoding utf8 $outLog
