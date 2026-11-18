@echo off
rem WT20 dual boot: runs prepare-windows.ps1 as administrator (asks for elevation once).
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0prepare-windows.ps1" %*
if %errorlevel% neq 0 pause
