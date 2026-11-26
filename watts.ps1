# Monitor de consumo leve (NAO acorda a GTX 1650 como o HWMonitor faz!)
# Uso: powershell -ExecutionPolicy Bypass -File .\watts.ps1
$null = [Windows.System.Power.PowerManager, Windows.System.Power, ContentType = WindowsRuntime]
$nv = Get-PnpDevice -Class Display | Where-Object { $_.FriendlyName -match 'NVIDIA' } | Select-Object -First 1
$dMap = @{ 0='?'; 1='D0 (ACORDADA!)'; 2='D1'; 3='D2'; 4='D3 (dormindo)'; 5='D3cold (OFF)' }

Write-Host "Monitor leve de bateria (Ctrl+C para sair) - NAO acorda a GTX 1650" -ForegroundColor Cyan
Write-Host ("-" * 86)

while ($true) {
    $b = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus
    $cpu = Get-CimInstance Win32_PerfFormattedData_Counters_ProcessorInformation | Where-Object { $_.Name -eq '_Total' }
    $dState = '?'
    if ($nv) {
        $pd = Get-PnpDeviceProperty -InstanceId $nv.InstanceId -KeyName 'DEVPKEY_Device_PowerData' -ErrorAction SilentlyContinue
        if ($pd -and $pd.Data.Length -ge 8) {
            $raw = [BitConverter]::ToInt32($pd.Data, 4)
            $dState = if ($dMap.ContainsKey($raw)) { $dMap[$raw] } else { "D$raw" }
        }
    }
    $w = [math]::Round($b.DischargeRate / 1000.0, 2)
    $remWh = [math]::Round($b.RemainingCapacity / 1000.0, 2)
    $hrsFull = if ($w -gt 0.5) { [math]::Round(60.0 / $w, 1) } else { 0 }
    $hrsRem  = if ($w -gt 0.5) { [math]::Round($remWh / $w, 1) } else { 0 }
    $mhz = [math]::Round(3000 * ($cpu.PercentProcessorPerformance / 100.0))
    $es = [Windows.System.Power.PowerManager]::EnergySaverStatus
    $pct = [Windows.System.Power.PowerManager]::RemainingChargePercent
    $ts = Get-Date -Format 'HH:mm:ss'
    $color = if ($b.PowerOnline) { 'Green' } elseif ($w -le 15.5) { 'Green' } elseif ($w -le 18.5) { 'Yellow' } else { 'Red' }
    $status = if ($b.PowerOnline) { 'TOMADA' } else { "-${w} W (~${hrsFull}h de 100% | ~${hrsRem}h rest.)" }
    Write-Host ("[$ts] $status | Bat: ${pct}% | CPU: $($cpu.PercentProcessorTime)% (~${mhz} MHz, C3:$($cpu.PercentC3Time)%) | GTX1650: $dState | ES: $es") -ForegroundColor $color
    Start-Sleep -Seconds 3
}
