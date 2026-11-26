@echo off
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0teste-teto-15w.ps1"
echo.
echo Teste concluido! Pode fechar esta janela e avisar no chat.
pause
