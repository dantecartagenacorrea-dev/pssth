@echo off
rem Ejecuta adb_cmds.bat en segundo plano (nunca bloquea al vigilante).
set N=%random%%random%
move /y adb_cmds.bat adb_run_%N%.bat >nul
if errorlevel 1 exit /b 0
echo [%time%] Ejecutando adb_run_%N%.bat
echo [%time%] inicio %N% >> adb_launch.log
start "adb" /min cmd /c adb_bg.bat %N%
