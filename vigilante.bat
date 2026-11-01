@echo off
title Vigilante LECTOR PDF (deja esta ventana abierta)
cd /d "%~dp0"
echo Esperando orden de verificacion... (cerrar la ventana para detener)
:loop
if exist adb_cmds.bat call adb_launch.bat
if exist run.flag (
  del /f /q run.flag
  if exist run.flag (
    echo No pude borrar run.flag; omito para no repetir en bucle.
    %SystemRoot%\System32\timeout.exe /t 30 /nobreak >nul
    goto loop
  )
  echo [%time%] Ejecutando verificar.bat
  call verificar.bat
  echo [%time%] Listo.
)
%SystemRoot%\System32\timeout.exe /t 3 /nobreak >nul
goto loop
