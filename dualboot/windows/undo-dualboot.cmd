@echo off
rem WT20 dual boot: runs undo-dualboot.ps1 as administrator (asks for elevation once).
net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0undo-dualboot.ps1" %*
if %errorlevel% neq 0 pause
