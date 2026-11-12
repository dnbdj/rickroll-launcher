@echo off
rem Opens the Rickroll launcher window without a console behind it.
rem Any arguments are passed straight through (e.g. Launcher.cmd -SelfTest).
start "" powershell -NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0Launcher.ps1" %*
