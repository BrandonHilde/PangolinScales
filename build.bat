@echo off
rem Builds PangolinScales.exe (requires the Odin compiler on PATH; SDL3 and stb come from its vendor: collection, the fonts are embedded)
rem The GUI build has no console window; PangolinScales-console.exe is the same program for --selftest output.
cd /d "%~dp0"
rem OdinUI is a git submodule in libs\odinui: fetch it on the first build after a plain clone
if not exist libs\odinui\odinui (
	git submodule update --init --recursive
	if errorlevel 1 exit /b 1
)
odin build src -out:PangolinScales.exe -o:speed -subsystem:windows -collection:odinui=libs/odinui
if errorlevel 1 exit /b 1
odin build src -out:PangolinScales-console.exe -o:speed -collection:odinui=libs/odinui
if errorlevel 1 exit /b 1
rem SDL3.dll has to sit next to the executables
for /f "delims=" %%i in ('odin root') do copy /Y "%%ivendor\sdl3\SDL3.dll" . >nul
echo Built PangolinScales.exe and PangolinScales-console.exe
