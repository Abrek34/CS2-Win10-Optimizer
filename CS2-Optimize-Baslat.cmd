@echo off
setlocal
set "SCRIPT=%~dp0CS2-Desktop-OneClick.ps1"

if not exist "%SCRIPT%" (
    echo Script bulunamadi:
    echo %SCRIPT%
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%SCRIPT%\"'"
