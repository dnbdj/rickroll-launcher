@echo off
rem Double-click launcher for Rickroll.ps1 (any arguments are passed straight through).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Rickroll.ps1" %*
echo.
pause
