# Vigia de audio: fica em segundo plano escutando os glitches do motor de audio do Windows.
# Se o som travar pipocando (muitos glitches por segundo, sem parar), da um "destravao":
# troca o formato da saida e volta, o que reabre o canal com a placa SEM fechar os apps.
# Log: %LOCALAPPDATA%\Energia\vigia-audio.log
$Limite    = 8    # glitches/s considerados "pipocando"
$Segundos  = 3    # por quantos segundos seguidos antes de agir
$Intervalo = 20   # segundos minimos entre dois destravoes

$dir = $PSScriptRoot
$logDir = Join-Path $env:LOCALAPPDATA 'Energia'; New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir 'vigia-audio.log'
function Log($m) {
    if ((Test-Path $log) -and (Get-Item $log).Length -gt 512KB) { Move-Item $log "$log.old" -Force }
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $m" | Out-File -Append -Encoding utf8 $log
}

# So um vigia por vez: encerra copias antigas deste script
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match 'vigia-audio\.ps1' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
[System.Diagnostics.Process]::GetCurrentProcess().PriorityClass = 'High'
Add-Type -Path "$dir\GlitchWatch.cs"
Add-Type -Path "$dir\SoftReset.cs"

function Start-Sessao {
    logman stop AudioGlitchVigia -ets 2>$null | Out-Null
    logman start AudioGlitchVigia -ets -rt -p '{553ca39b-c608-566d-18ae-7b9a03a39acd}' 0xffffffffffffffff 5 2>$null | Out-Null
    if ([GlitchWatch]::Start('AudioGlitchVigia')) { Log 'escutando glitches' } else { Log "erro ao escutar: $([GlitchWatch]::Error)" }
}

Log 'vigia iniciado'
Start-Sessao
$seguidos = 0; $ultimo = [datetime]::MinValue; $checagem = Get-Date
while ($true) {
    Start-Sleep -Seconds 1
    $n = [GlitchWatch]::Take()
    if ($n -gt 0) { Log "glitches: $n/s (tipo $([GlitchWatch]::LastType))" }
    if ($n -ge $Limite) { $seguidos++ } else { $seguidos = 0 }

    if ($seguidos -ge $Segundos -and ((Get-Date) - $ultimo).TotalSeconds -ge $Intervalo) {
        try {
            $id = [SoftReset]::DefaultId()
            $r = [SoftReset]::Run($id)
            Log "PIPOCANDO ($n glitches/s por ${seguidos}s, tipo $([GlitchWatch]::LastType)) -> destravao: $r"
            Start-Sleep -Seconds 3; [void][GlitchWatch]::Take(); Start-Sleep -Seconds 2
            Log "   depois do destravao: $([GlitchWatch]::Take()) glitches em 2s"
        } catch { Log "erro no destravao: $_" }
        $ultimo = Get-Date; $seguidos = 0
    }

    # a cada minuto confere se a escuta continua viva
    if (((Get-Date) - $checagem).TotalSeconds -ge 60) {
        $checagem = Get-Date
        $vivo = (logman query AudioGlitchVigia -ets 2>$null | Out-String) -match 'Executando|Em execu|Running'
        if (-not $vivo -or [GlitchWatch]::Error) { Log "escuta caiu ($([GlitchWatch]::Error)), religando"; [GlitchWatch]::Error = ''; Start-Sessao }
    }
}
