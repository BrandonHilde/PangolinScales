@echo off
rem Updates this app to the newest version on GitHub: pulls its latest commits, then moves the code it shares with the
rem other Pangolin tools (libs/shared) and OdinUI (libs/odinui) to the versions those commits expect. A plain git pull
rem leaves the submodules where they were, and the build then fails. build.bat on its own builds whatever is here now,
rem so updating is up to you: run this, then build.bat.
cd /d "%~dp0"
git pull --ff-only
if errorlevel 1 (
	echo.
	echo Could not update: this copy has changes or commits of its own that a plain update would mix in.
	echo Commit or stash them, or merge by hand, then run update.bat again.
	exit /b 1
)
git submodule update --init --recursive
if errorlevel 1 exit /b 1
echo Up to date. Run build.bat to build it.
exit /b 0
