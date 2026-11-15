@echo off
rem ftp_setup.cmd: the production server's FTP details for the FlameKit FTP tool. See ftp_setup.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ftp_setup.ps1"
echo.
pause
