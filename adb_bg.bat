@echo off
cd /d "%~dp0"
call adb_run_%1.bat > adb_out_%1.txt 2>&1
copy /y adb_out_%1.txt adb_out.txt >nul
echo [%time%] fin %1 >> adb_launch.log
del /q adb_run_%1.bat
