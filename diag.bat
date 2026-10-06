@echo off
cd /d "%~dp0"
set SDK=%LOCALAPPDATA%\Android\sdk
> diag.log echo === diag2 ===
dir /b /s "%SDK%\system-images" | findstr /i "x86_64 arm64" | findstr /i "system.img" >> diag.log 2>&1
dir /b "%SDK%\platforms" "%SDK%\build-tools" "%SDK%\licenses" "%SDK%\cmdline-tools" >> diag.log 2>&1
dir /b "%USERPROFILE%\.android\avd" >> diag.log 2>&1
"%SDK%\emulator\emulator.exe" -list-avds >> diag.log 2>&1
"%SDK%\emulator\emulator.exe" -accel-check >> diag.log 2>&1
echo === FIN === >> diag.log
