@echo off
rem Instala en el emulador el APK compilado por GitHub Actions.
rem Uso: descargar lector-android.zip desde Actions a la carpeta Descargas y doble clic aqui.
cd /d "%~dp0"
set SDK=%LOCALAPPDATA%\Android\sdk
set ADB=%SDK%\platform-tools\adb.exe
set ZIP=%USERPROFILE%\Downloads\lector-android.zip
set APK=%USERPROFILE%\Downloads\app-release.apk

if exist "%ZIP%" (
  powershell -NoProfile -Command "Expand-Archive -Force '%ZIP%' '%USERPROFILE%\Downloads'"
)
if not exist "%APK%" (
  echo No encuentro %APK%
  echo Descarga lector-android.zip desde GitHub Actions a Descargas y vuelve a ejecutar.
  pause & exit /b 1
)

"%ADB%" start-server >nul 2>&1
"%ADB%" devices | findstr /r "emulator.*device" >nul
if errorlevel 1 (
  echo Arrancando el emulador...
  start "" /min cmd /c emu.bat
  "%ADB%" wait-for-device
  :espera
  for /f %%b in ('"%ADB%" shell getprop sys.boot_completed 2^>nul') do set BOOT=%%b
  if not "%BOOT%"=="1" ( timeout /t 3 >nul & goto espera )
)

echo Instalando...
"%ADB%" install -r "%APK%"
if errorlevel 1 ( echo Fallo la instalacion. & pause & exit /b 1 )

echo Copiando PDF de prueba y abriendo Lector...
"%ADB%" push "pruebas\1_pdf_texto_es.pdf" /sdcard/Download/ >nul
"%ADB%" shell am start -n com.lectorpdf.lectorPdf/com.lectorpdf.lector_pdf.MainActivity >nul
echo.
echo Listo. En el emulador: Abrir documento ^> Download ^> 1_pdf_texto_es.pdf ^> Play.
pause
