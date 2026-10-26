@echo off
cd /d "%~dp0"
set SDK=%LOCALAPPDATA%\Android\sdk
set ANDROID_HOME=%SDK%
set ANDROID_SDK_ROOT=%SDK%
set ADB=%SDK%\platform-tools\adb.exe
set AVD=%USERPROFILE%\.android\avd
set FL=%USERPROFILE%\flutter\bin\flutter.bat
rem JDK propio si existe; si no, el JAVA_HOME del sistema.
if exist "%~dp0tool-jdk\jdk-17.0.20.1+1" set JAVA_HOME=%~dp0tool-jdk\jdk-17.0.20.1+1
set PATH=%JAVA_HOME%\bin;%PATH%
set LOG=emu.log
> %LOG% echo === emu %date% %time% ===

if not exist "%AVD%\lector.avd" (
  mkdir "%AVD%\lector.avd"
  > "%AVD%\lector.ini" echo avd.ini.encoding=UTF-8
  >> "%AVD%\lector.ini" echo path=%AVD%\lector.avd
  >> "%AVD%\lector.ini" echo path.rel=avd\lector.avd
  >> "%AVD%\lector.ini" echo target=android-35
  > "%AVD%\lector.avd\config.ini" echo AvdId=lector
  >> "%AVD%\lector.avd\config.ini" echo avd.ini.displayname=Lector
  >> "%AVD%\lector.avd\config.ini" echo avd.ini.encoding=UTF-8
  >> "%AVD%\lector.avd\config.ini" echo PlayStore.enabled=true
  >> "%AVD%\lector.avd\config.ini" echo abi.type=x86_64
  >> "%AVD%\lector.avd\config.ini" echo hw.cpu.arch=x86_64
  >> "%AVD%\lector.avd\config.ini" echo hw.cpu.ncore=4
  >> "%AVD%\lector.avd\config.ini" echo hw.ramSize=2048
  >> "%AVD%\lector.avd\config.ini" echo hw.lcd.density=420
  >> "%AVD%\lector.avd\config.ini" echo hw.lcd.width=1080
  >> "%AVD%\lector.avd\config.ini" echo hw.lcd.height=2340
  >> "%AVD%\lector.avd\config.ini" echo hw.keyboard=yes
  >> "%AVD%\lector.avd\config.ini" echo hw.gpu.enabled=yes
  >> "%AVD%\lector.avd\config.ini" echo hw.gpu.mode=auto
  >> "%AVD%\lector.avd\config.ini" echo hw.audioOutput=yes
  >> "%AVD%\lector.avd\config.ini" echo hw.camera.back=virtualscene
  >> "%AVD%\lector.avd\config.ini" echo hw.camera.front=emulated
  >> "%AVD%\lector.avd\config.ini" echo hw.sdCard=yes
  >> "%AVD%\lector.avd\config.ini" echo sdcard.size=512M
  >> "%AVD%\lector.avd\config.ini" echo disk.dataPartition.size=6G
  >> "%AVD%\lector.avd\config.ini" echo image.sysdir.1=system-images\android-35\google_apis_playstore\x86_64\
  >> "%AVD%\lector.avd\config.ini" echo tag.id=google_apis_playstore
  >> "%AVD%\lector.avd\config.ini" echo tag.display=Google Play
  >> %LOG% echo AVD creado
)

"%ADB%" start-server >> %LOG% 2>&1
"%ADB%" devices | findstr /C:"emulator-" >nul
if errorlevel 1 (
  >> %LOG% echo Arrancando emulador...
  start "Emulador Lector" "%SDK%\emulator\emulator.exe" -avd lector -no-boot-anim -no-snapshot-load
)
set /a N=0
:esperar
set /a N+=1
if %N% gtr 60 ( >> %LOG% echo ERROR: el emulador no arranco en 5 min & goto fin )
timeout /t 5 /nobreak >nul
"%ADB%" -e shell getprop sys.boot_completed 2>nul | findstr "1" >nul
if errorlevel 1 goto esperar
>> %LOG% echo Emulador listo tras %N% intentos
"%ADB%" -e shell getprop ro.build.version.release >> %LOG% 2>&1

>> %LOG% echo --- compilando APK debug ---
call "%FL%" build apk --debug >> %LOG% 2>&1
>> %LOG% echo --- instalando ---
if not exist build\app\outputs\flutter-apk\app-debug.apk goto fin
"%ADB%" -e install -r -g build\app\outputs\flutter-apk\app-debug.apk >> %LOG% 2>&1
"%ADB%" -e shell mkdir -p /sdcard/Download/pruebas >> %LOG% 2>&1
"%ADB%" -e push pruebas /sdcard/Download/ >> %LOG% 2>&1
"%ADB%" -e logcat -c
"%ADB%" -e shell monkey -p com.lectorpdf.lectorPdf -c android.intent.category.LAUNCHER 1 >> %LOG% 2>&1
timeout /t 15 /nobreak >nul
"%ADB%" -e exec-out screencap -p > emu_pantalla.png
"%ADB%" -e logcat -d -v brief *:E flutter:V > emu_logcat.txt
:fin
>> %LOG% echo === FIN ===
