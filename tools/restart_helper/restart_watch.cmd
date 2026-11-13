@echo off
rem restart_watch.cmd: FlameKit's restart helper. Leave this window open while working on FlameKit.
rem It restarts the game client and the local dedicated server when Claude asks for it (after the owner said yes),
rem without using the screen, the mouse or the keyboard. Close this window to stop it. The work is in restart_helper.ps1.
cd /d "%~dp0"
title FlameKit restart helper
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0restart_helper.ps1"
echo.
echo The restart helper stopped. Press a key to close this window.
pause >nul
