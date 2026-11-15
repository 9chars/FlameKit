@echo off
rem upload.cmd: puts what Claude left in the outbox on the production server and fetches the server's log. See upload.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0upload.ps1"
echo.
pause
