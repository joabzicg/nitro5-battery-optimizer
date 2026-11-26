# Espera a bateria chegar a 100% na tomada e gera o relatorio na Area de Trabalho.
$desk = [Environment]::GetFolderPath('Desktop')
$fim = (Get-Date).AddHours(8)
while ((Get-Date) -lt $fim) {
    $b = Get-CimInstance Win32_Battery
    $s = Get-CimInstance -Namespace root\wmi -ClassName BatteryStatus
    if ($b.EstimatedChargeRemaining -ge 100 -and $s.PowerOnline -and -not $s.Charging) { break }
    if (-not $s.PowerOnline) { exit }   # tirou da tomada antes de encher: ciclo interrompido
    Start-Sleep -Seconds 60
}
Start-Sleep -Seconds 300   # deixa o medidor da bateria assentar
powercfg /batteryreport /output (Join-Path $desk 'bateria-apos-ciclo.html') | Out-Null
