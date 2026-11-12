@echo off
rem Double-click launcher for Stop-Rickroll.ps1 (any arguments are passed straight through).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Stop-Rickroll.ps1" %*
echo.
pause
