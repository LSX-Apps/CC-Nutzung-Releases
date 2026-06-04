@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ccusage-setup-wizard.ps1"
if errorlevel 1 (
  echo.
  echo Setup wurde mit einem Fehler beendet.
  pause
)

