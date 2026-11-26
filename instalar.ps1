#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Instalador completo do Nitro 5 Battery Optimizer (teto <= 15W na bateria, 45W+ na tomada).
.DESCRIPTION
    1. Baixa o RyzenAdj oficial (FlyGoat/RyzenAdj) para .\ryzenadj\
    2. Registra a tarefa agendada "Energia Automatica" (roda em segundo plano no logon, como Admin)
    3. Instala o "Vigia de Audio" (destrava glitches de audio via ETW/WASAPI sem fechar apps)
    4. Fixa navegadores e apps Electron comuns na GPU integrada (GpuPreference=1)
#>

$ErrorActionPreference = 'Stop'
$base = $PSScriptRoot

Write-Host "=== 1. Baixando RyzenAdj oficial (FlyGoat/RyzenAdj) ===" -ForegroundColor Cyan
$ryzenDir = Join-Path $base 'ryzenadj'
if (-not (Test-Path (Join-Path $ryzenDir 'ryzenadj.exe'))) {
    New-Item -ItemType Directory -Force $ryzenDir | Out-Null
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $rel = Invoke-RestMethod -Uri 'https://api.github.com/repos/FlyGoat/RyzenAdj/releases/latest' -Headers @{ 'User-Agent' = 'nitro5-battery-optimizer' }
    $asset = $rel.assets | Where-Object { $_.name -match '^ryzenadj-win64\.zip$' -or ($_.name -match 'win64\.zip$' -and $_.name -notmatch 'lib') } | Select-Object -First 1
    $zip = Join-Path $env:TEMP $asset.name
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -UseBasicParsing
    Expand-Archive -Path $zip -DestinationPath $ryzenDir -Force
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    Write-Host "  OK: RyzenAdj $($rel.tag_name) instalado em $ryzenDir" -ForegroundColor Green
} else {
    Write-Host "  OK: ryzenadj.exe ja presente." -ForegroundColor Green
}

Write-Host "=== 2. Registrando tarefa agendada 'Energia Automatica' ===" -ForegroundColor Cyan
$scriptEnergia = Join-Path $base 'auto-energia.ps1'
$a = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$scriptEnergia`""
$t = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$p = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
$s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName 'Energia Automatica' -Action $a -Trigger $t -Principal $p -Settings $s -Description 'Alterna automaticamente entre modo economia (<=15W) na bateria e desempenho maximo na tomada.' -Force | Out-Null
Stop-ScheduledTask -TaskName 'Energia Automatica' -ErrorAction SilentlyContinue
Start-ScheduledTask -TaskName 'Energia Automatica'
Write-Host "  OK: Tarefa 'Energia Automatica' ativa." -ForegroundColor Green

Write-Host "=== 3. Instalando 'Vigia de Audio' ===" -ForegroundColor Cyan
$vigiaInstaller = Join-Path $base 'vigia\instalar-vigia.ps1'
if (Test-Path $vigiaInstaller) {
    & $vigiaInstaller
    Write-Host "  OK: Tarefa 'Vigia de Audio' ativa." -ForegroundColor Green
}

Write-Host "=== 4. Fixando apps do dia a dia na iGPU (GpuPreference=1) ===" -ForegroundColor Cyan
$regPath = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'
if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }
$candidates = @(
    "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "$env:LOCALAPPDATA\Microsoft\WindowsApps\Spotify.exe",
    "$env:LOCALAPPDATA\Programs\antigravity\Antigravity.exe"
)
$running = Get-Process -Name Antigravity,claude,Spotify,chrome,msedge,msedgewebview2,wallpaper64,ms-teams,Discord,ChatGPT,copilotapp,PowerToys -ErrorAction SilentlyContinue |
    Where-Object { $_.Path } | Select-Object -ExpandProperty Path -Unique
foreach ($exe in (($candidates + $running) | Where-Object { $_ -and (Test-Path $_) } | Sort-Object -Unique)) {
    Set-ItemProperty -Path $regPath -Name $exe -Value 'GpuPreference=1;'
}

Write-Host "`nInstalacao concluida! Use .\watts.ps1 para monitorar o consumo sem acordar a GTX 1650." -ForegroundColor Green
