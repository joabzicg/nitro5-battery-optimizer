#Requires -RunAsAdministrator
# Teste A/B/C de hardware na bateria (compara GTX 1650 em D3 vs Desabilitada no PnP)
# Grava o resultado em %LOCALAPPDATA%\Energia\teste-gpu.log
$log = Join-Path $env:LOCALAPPDATA 'Energia\teste-gpu.log'
New-Item -ItemType Directory -Force (Split-Path $log) | Out-Null
function Out($m) { Write-Host $m; $m | Out-File -Append -Encoding utf8 $log }

"" | Out-File -Encoding utf8 $log
Out "=== TESTE GPU BATERIA $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

$b0 = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus
if ($b0.PowerOnline) {
    Out "ERRO: Notebook ainda esta na TOMADA! Tire da tomada e rode de novo."
    exit 1
}

# Garante que HWMonitor e NvContainer nao estao atrapalhando o teste
Get-Process -Name 'HWMonitor','NVIDIA Overlay','nvsphelper64','nvcontainer','AMDRSServ','AMDRSSrcExt' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Stop-Service -Name 'NvContainerLocalSystem' -Force -ErrorAction SilentlyContinue

# Aplica o novo teto SMU (incluindo apu-slow-limit=10000!)
$ra = Join-Path $PSScriptRoot 'ryzenadj\ryzenadj.exe'
if (Test-Path $ra) {
    & $ra --stapm-limit=10000 --fast-limit=11000 --slow-limit=10000 --apu-slow-limit=10000 --vrm-current=22000 --vrmmax-current=30000 --vrmsoc-current=10000 --vrmsocmax-current=15000 --tctl-temp=68 --power-saving 2>$null | Out-Null
}

$gtx = Get-PnpDevice -Class Display | Where-Object { $_.FriendlyName -match 'NVIDIA' } | Select-Object -First 1
$nvAudio = Get-PnpDevice | Where-Object { $_.InstanceId -match 'PCI\\VEN_10DE&DEV_10FA' } | Select-Object -First 1

function Medir-Fase($nome, [int]$settleSec = 10) {
    Out "--- $nome (aguardando ${settleSec}s para EC estabilizar) ---"
    Start-Sleep -Seconds $settleSec
    $ws = @()
    for ($i = 1; $i -le 4; $i++) {
        $b = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus
        $cpu = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation | Where-Object { $_.Name -eq '_Total' }
        $gNow = Get-PnpDevice -InstanceId $gtx.InstanceId -ErrorAction SilentlyContinue
        $pd = Get-PnpDeviceProperty -InstanceId $gtx.InstanceId -KeyName 'DEVPKEY_Device_PowerData' -ErrorAction SilentlyContinue
        $d = if ($pd -and $pd.Data.Length -ge 8) { [BitConverter]::ToInt32($pd.Data, 4) } else { -1 }
        $w = [math]::Round($b.DischargeRate / 1000.0, 2)
        $ws += $w
        $mhz = [math]::Round(3000 * ($cpu.PercentProcessorPerformance / 100.0))
        Out ("  Amostra ${i}: -${w} W | CPU=$($cpu.PercentProcessorTime)% (~${mhz}MHz, C3:$($cpu.PercentC3Time)%) | GTX_Status=$($gNow.Status) | GTX_D=$d")
        if ($i -lt 4) { Start-Sleep -Seconds 3 }
    }
    $avg = [math]::Round(($ws | Measure-Object -Average).Average, 2)
    $min = [math]::Round(($ws | Measure-Object -Minimum).Minimum, 2)
    $max = [math]::Round(($ws | Measure-Object -Maximum).Maximum, 2)
    Out "  >> RESUMO ${nome}: Media=-${avg} W | Min=-${min} W | Max=-${max} W (~$(if($avg -gt 0){[math]::Round(60/$avg,1)}else{0})h em 60Wh)"
    return $avg
}

# FASE A: GTX 1650 HABILITADA (Optimus D3) + NV_Audio desabilitado
if ($nvAudio -and $nvAudio.Status -eq 'OK') { Disable-PnpDevice -InstanceId $nvAudio.InstanceId -Confirm:$false -ErrorAction SilentlyContinue | Out-Null }
if ($gtx.Status -ne 'OK') { Enable-PnpDevice -InstanceId $gtx.InstanceId -Confirm:$false -ErrorAction SilentlyContinue | Out-Null }
$avgA = Medir-Fase 'FASE_A_OPTIMUS_D3' 10

# FASE B: GTX 1650 DESABILITADA NO HARDWARE (Disable-PnpDevice -> impossivel qualquer app acordar!)
Out "Desabilitando GTX 1650 no PnP para testar consumo real..."
Disable-PnpDevice -InstanceId $gtx.InstanceId -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
$avgB = Medir-Fase 'FASE_B_GTX_DESABILITADA' 12

# Compara e decide automaticamente com seguranca!
if ($avgB -le ($avgA + 0.6)) {
    Out "VENCEDOR: FASE_B (GTX DESABILITADA no PnP! -$avgB W vs -$avgA W -> 0% chance de ativar na bateria!)"
    Out "Mantendo GTX desabilitada nesta sessao de bateria (sera reabilitada ao voltar pra tomada)."
} else {
    Out "VENCEDOR: FASE_A (BIOS precisa do driver NVIDIA carregado para D3cold! Fase B subiu para -$avgB W vs -$avgA W)"
    Out "Reabilitando GTX 1650 imediatamente para voltar ao D3cold de baixo consumo..."
    Enable-PnpDevice -InstanceId $gtx.InstanceId -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
    Start-Sleep -Seconds 5
    $avgRestore = Medir-Fase 'FASE_A_RESTAURADA' 6
}

# Recarrega a tarefa Energia Automatica com o novo auto-energia.ps1 (apu-slow-limit atualizado)
Stop-ScheduledTask -TaskName 'Energia Automatica' -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match 'auto-energia\.ps1' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Milliseconds 500
Start-ScheduledTask -TaskName 'Energia Automatica'

Out "=== RYZENADJ --INFO POS-TESTE ==="
if (Test-Path $ra) { (& $ra --info 2>&1 | Select-String 'LIMIT|VALUE|SETPOINT') | ForEach-Object { Out $_.Line } }
Out "=== FIM ==="
