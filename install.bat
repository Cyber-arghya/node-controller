@echo off
TITLE Native PC Controller Installer
:: Check for Administrator privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [*] Requesting Administrator privileges...
    powershell -Command "Start-Process '%~dpnx0' -Verb RunAs"
    exit /b
)

echo [+] Running PowerShell Deployment...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0server.ps1"
pause