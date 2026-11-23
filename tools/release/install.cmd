@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" -AskDesktopShortcut %*
if errorlevel 1 echo Install failed: see the message above.
pause
