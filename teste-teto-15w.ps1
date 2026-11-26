#Requires -RunAsAdministrator
# Recarrega auto-energia.ps1 com o novo teto rigido (6.5W SMU) e faz um stress test de 100% CPU (12 threads)
# na bateria para PROVAR que o PC inteiro fica <= 15W mesmo com "um bilhao de tasks".
$log = Join-Path $env:LOCALAPPDATA 'Energia\teste-teto-15w.log'
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
function Out($m) { Write-Host $m; $m | Out-File -Append -Encoding utf8 $log }

"" | Out-File -Encoding utf8 $log
Out "=== TESTE TETO RIGIDO 15W $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

# 1. Recarrega tarefa Energia Automatica com o novo auto-energia.ps1
Stop-ScheduledTask -TaskName 'Energia Automatica' -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'auto-energia\.ps1' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 500
Start-ScheduledTask -TaskName 'Energia Automatica'
Start-Sleep -Seconds 6

$b0 = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus
if ($b0.PowerOnline) {
    Out "AVISO: Notebook ainda esta na TOMADA! Novo auto-energia.ps1 JA foi recarregado."
    Out "Tire da tomada e rode este teste de novo para validar o stress de 100% CPU."
    exit 0
}

$null = [Windows.System.Power.PowerManager, Windows.System.Power, ContentType = WindowsRuntime]
$gtx = Get-PnpDevice -Class Display | Where-Object { $_.FriendlyName -match 'NVIDIA' } | Select-Object -First 1
$ra = Join-Path $PSScriptRoot 'ryzenadj\ryzenadj.exe'

function Snap($tag) {
    $b = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus
    $cpu = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation | Where-Object { $_.Name -eq '_Total' }
    $pd = Get-PnpDeviceProperty -InstanceId $gtx.InstanceId -KeyName 'DEVPKEY_Device_PowerData' -EA SilentlyContinue
    $d = if ($pd -and $pd.Data.Length -ge 8) { [BitConverter]::ToInt32($pd.Data, 4) } else { -1 }
    $w = [math]::Round($b.DischargeRate / 1000.0, 2)
    $mhz = [math]::Round(3000 * ($cpu.PercentProcessorPerformance / 100.0))
    $br = (Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorBrightness -EA SilentlyContinue).CurrentBrightness
    Out ("  [{0}] -{1:N2} W (~{2}h em 60Wh) | CPU={3}% (~{4}MHz, C3:{5}%) | GTX_D={6} | ES={7} | Brilho={8}%" -f $tag, $w, $(if($w -gt 0.5){[math]::Round(60/$w,1)}else{0}), $cpu.PercentProcessorTime, $mhz, $cpu.PercentC3Time, $d, [Windows.System.Power.PowerManager]::EnergySaverStatus, $br)
    return $w
}

Out "--- 1. LEITURA EM USO NORMAL (aguardando 8s) ---"
Start-Sleep -Seconds 8
$wNorm1 = Snap 'NORMAL_1'
Start-Sleep -Seconds 3
$wNorm2 = Snap 'NORMAL_2'

Out "--- 2. STRESS TEST 100% CPU EM TODAS AS 12 THREADS (15s) ---"
$jobs = @()
for ($t = 0; $t -lt 12; $t++) {
    $jobs += Start-Job -ScriptBlock {
        $end = (Get-Date).AddSeconds(16)
        $x = 1.0001
        while ((Get-Date) -lt $end) { $x = [Math]::Sqrt($x * 1.000001 + 1.0) }
    }
}
Start-Sleep -Seconds 5
$wsStress = @()
for ($i = 1; $i -le 4; $i++) {
    $wsStress += (Snap "STRESS_100PCT_$i")
    if ($i -lt 4) { Start-Sleep -Seconds 3 }
}
$jobs | Wait-Job -Timeout 10 | Out-Null
$jobs | Remove-Job -Force -ErrorAction SilentlyContinue

$maxStress = ($wsStress | Measure-Object -Maximum).Maximum
$avgStress = [math]::Round(($wsStress | Measure-Object -Average).Average, 2)
Out "=== RESUMO STRESS 100% CPU ==="
Out "  Media sob 100% CPU: -$avgStress W | Pico maximo: -$maxStress W"
if ($maxStress -le 15.0) {
    Out "  STATUS: APROVADO! Teto rigido <= 15W mantido mesmo em 100% CPU!"
} else {
    Out "  STATUS: PASSOU DE 15W (pico -$maxStress W) -> precisa baixar STAPM mais um pouco."
}

Out "=== RYZENADJ --INFO ==="
if (Test-Path $ra) { (& $ra --info 2>&1 | Select-String 'LIMIT|VALUE|SETPOINT') | ForEach-Object { Out $_.Line } }
Out "=== FIM ==="
