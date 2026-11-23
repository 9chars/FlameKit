@echo off
rem build.cmd: compiles FlameKit's native (C++) mod with Visual Studio's compiler into out\flamekit_native\.
rem Run it directly, or leave build_watch.cmd open and it runs whenever a build is asked for.
setlocal
cd /d "%~dp0"
set "ID=flamekit_native"
set "SDK=%~dp0..\EMF-0.6.6\sdk\include"
set "OUT=%~dp0out\%ID%"

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" goto :novswhere
set "VSDIR="
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSDIR=%%i"
if not defined VSDIR goto :nocpp
echo Visual Studio: %VSDIR%
call "%VSDIR%\VC\Auxiliary\Build\vcvars64.bat" >nul
if errorlevel 1 goto :novars
if not exist "%SDK%\emf\emf.hpp" goto :nosdk

if not exist "%OUT%" mkdir "%OUT%"
if not exist "%~dp0obj" mkdir "%~dp0obj"
echo Compiling %ID% ...
cl /nologo /std:c++20 /O2 /MT /EHsc /utf-8 /W3 /permissive- /LD /DMOD_ID=\"%ID%\" /I"%SDK%" /Fo"%~dp0obj/" /Fe"%OUT%\%ID%.dll" "%~dp0src\*.cpp" "%~dp0src\zstddeclib.c" /link /NOLOGO user32.lib gdi32.lib winhttp.lib
if errorlevel 1 goto :failed
copy /y "%~dp0mod.json" "%OUT%\mod.json" >nul
echo BUILD OK: %OUT%\%ID%.dll
rem (0.15.454) the test of EMF's own update (src\emf_update.hpp), in obj\emf_update_test only: needs both EMF packages
if not exist "%~dp0tests\emf_update_test.cpp" goto :notest
if not exist "%~dp0..\EMF-0.6.6\game\emf\emf_core.dll" goto :nopackages
if not exist "%~dp0..\EMF-0.6.19\game\emf\emf_core.dll" goto :nopackages
if not exist "%~dp0obj\test" mkdir "%~dp0obj\test"
echo Compiling emf_update_test ...
cl /nologo /std:c++20 /O2 /MT /EHsc /utf-8 /W3 /permissive- /Fo"%~dp0obj\test/" /Fe"%~dp0obj\emf_update_test.exe" "%~dp0tests\emf_update_test.cpp" /link /NOLOGO winhttp.lib
if errorlevel 1 goto :testfailed
"%~dp0obj\emf_update_test.exe" "%~dp0obj\emf_update_test" "%~dp0..\EMF-0.6.6\game" "%~dp0..\EMF-0.6.19\game"
if errorlevel 1 goto :testfailed
echo TESTS OK: emf_update_test
goto :notest
:nopackages
echo TESTS SKIPPED: emf_update_test needs ..\EMF-0.6.6 and ..\EMF-0.6.19 next to this folder
:notest
rem the client gets it through FlameKit's own updater (from GitHub), as a player's does: nothing is copied there
exit /b 0

:failed
echo BUILD FAILED
exit /b 1
:testfailed
echo BUILD OK, TESTS FAILED: emf_update_test (the DLL was built; see above)
exit /b 6
:novswhere
echo ERROR: vswhere.exe not found. Is Visual Studio installed?
exit /b 2
:nocpp
echo ERROR: no Visual Studio with the C++ tools found. In the Visual Studio Installer, add the workload "Desktop development with C++".
exit /b 3
:novars
echo ERROR: vcvars64.bat failed.
exit /b 4
:nosdk
echo ERROR: EMF SDK not found: %SDK%\emf\emf.hpp
exit /b 5
