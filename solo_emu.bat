@echo off
cd /d "%~dp0"
if exist emu.flag (
  del /f /q emu.flag
  call emu.bat
)
