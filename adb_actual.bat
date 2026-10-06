@echo off
cd /d "%~dp0"
call adb_env.bat
"%ADB%" -e shell input tap 400 1370
timeout /t 8 /nobreak >nul
"%ADB%" -e shell uiautomator dump /sdcard/ui.xml >nul
"%ADB%" -e shell cat /sdcard/ui.xml > emu_ui.xml
"%ADB%" -e shell input keyevent BACK
timeout /t 3 /nobreak >nul
"%ADB%" -e shell input tap 540 672
timeout /t 8 /nobreak >nul
"%ADB%" -e shell uiautomator dump /sdcard/ui.xml >nul
"%ADB%" -e shell cat /sdcard/ui.xml > emu_ui2.xml
echo HECHO
