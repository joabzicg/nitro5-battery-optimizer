@echo off
:: Aplica tudo a nivel de hardware como Admin (RyzenAdj 10W SMU + GTX 1650 D3 + NVMe PS4 + reinicia Energia Automatica)
:: e abre o monitor leve watts.ps1 (que NAO acorda a GTX 1650).
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
echo Aplicando ajustes de hardware (RyzenAdj SMU 10W + GTX 1650 D3 + reinicio Energia Automatica)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0apply-and-verify.ps1"
echo.
echo === RESUMO DO HARDWARE (SMU / GTX 1650 / WATTS) ===
type "%LOCALAPPDATA%\Energia\hardware-verify.log"
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0watts.ps1"
