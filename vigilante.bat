@echo off
title Vigilante LECTOR PDF (deja esta ventana abierta)
cd /d "%~dp0"
echo Esperando orden de verificacion... (cerrar la ventana para detener)
:loop
if exist run.flag (
  del /f /q run.flag
  if exist run.flag (
    echo No pude borrar run.flag; omito para no repetir en bucle.
    timeout /t 30 /nobreak >nul
    goto loop
  )
  echo [%time%] Ejecutando verificar.bat
  call verificar.bat
  echo [%time%] Listo.
)
timeout /t 3 /nobreak >nul
goto loop
