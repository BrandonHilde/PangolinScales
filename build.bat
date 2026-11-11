@echo off
rem Builds PangolinScales.exe (requires the Odin compiler on PATH; SDL3 and stb come from its vendor: collection, the fonts are embedded)
rem The GUI build has no console window; PangolinScales-console.exe is the same program for --selftest output.
cd /d "%~dp0"
rem OdinUI and the shared Pangolin code are git submodules in libs: fetch them on the first build after a plain clone
set fetch=
if not exist libs\odinui\odinui set fetch=1
if not exist libs\shared\src set fetch=1
if defined fetch (
	git submodule update --init --recursive
	if errorlevel 1 exit /b 1
)
rem A pull doesn't move the submodules: say so when libs/shared isn't the version this app's code expects
set "sub="
for /f "delims=" %%s in ('git submodule status libs/shared 2^>nul') do set "sub=%%s"
if "%sub:~0,1%"=="+" (
	echo Note: libs\shared is not the version this app's code expects, so the build may fail.
	echo Run update.bat to bring both up to date, or "git submodule update" to match this code.
)
rem Odin compiles one folder as one package, so the shared code is copied in
call libs\shared\sync.bat
rem The commit goes into About and --version
set "commit="
for /f "delims=" %%c in ('git rev-parse --short HEAD 2^>nul') do set "commit=-define:APP_COMMIT=%%c"
rem The icon is already compiled (assets\icon\app.res), so this needs no resource compiler
call :compile PangolinScales.exe -subsystem:windows
if errorlevel 1 exit /b 1
call :compile PangolinScales-console.exe
if errorlevel 1 exit /b 1
rem SDL3.dll has to sit next to the executables
for /f "delims=" %%i in ('odin root') do copy /Y "%%ivendor\sdl3\SDL3.dll" . >nul
echo Built PangolinScales.exe and PangolinScales-console.exe
exit /b 0

:compile
rem %1 is the output, %2 any extra flags. The first try's output is only shown if it worked: if it failed, the build
rem without the icon shows a real compile error once, or shows that the icon was the only problem.
set "log=%TEMP%\pangolin_build_%RANDOM%.log"
odin build src -out:%1 -o:speed %2 -collection:odinui=libs/odinui %commit% -resource:assets/icon/app.res >"%log%" 2>&1
if not errorlevel 1 (
	type "%log%"
	del "%log%"
	exit /b 0
)
del "%log%"
odin build src -out:%1 -o:speed %2 -collection:odinui=libs/odinui %commit%
if errorlevel 1 exit /b 1
echo Note: %1 was built without its icon, because linking assets\icon\app.res failed. Everything else works.
exit /b 0
