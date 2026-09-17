@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
if errorlevel 1 (
  echo Installation failed. Press any key to close.
  pause >nul
  exit /b 1
)
exit /b 0
