@echo off
rem build_watch.cmd: leave this window open while working on FlameKit's native part.
rem Whenever a file named build.request appears in this folder, it runs build.cmd and writes
rem the compiler's output to build.log and the result code to build.done.
cd /d "%~dp0"
title FlameKit native build watcher
echo FlameKit native build watcher
echo Leave this window open. Close it to stop.
echo.
:loop
if exist build.request call :build
timeout /t 2 /nobreak >nul
goto :loop

:build
del build.request
if exist build.done del build.done
echo [%time%] building...
call build.cmd > build.log 2>&1
set "RESULT=%errorlevel%"
echo %RESULT%> build.done
if "%RESULT%"=="0" echo [%time%] build OK and deployed
if not "%RESULT%"=="0" echo [%time%] build ended with code %RESULT% (see build.log)
exit /b 0
