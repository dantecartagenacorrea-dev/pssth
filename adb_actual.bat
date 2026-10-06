@echo off
cd /d "%~dp0"
call adb_env.bat
call "%FL%" build apk --debug
"%ADB%" -e install -r -g build\app\outputs\flutter-apk\app-debug.apk
"%ADB%" -e shell am force-stop com.lectorpdf.lector_pdf
"%ADB%" -e logcat -c
"%ADB%" -e shell am start -a android.intent.action.VIEW -d content://media/external/file/1000000035 -t application/pdf --grant-read-uri-permission -n com.lectorpdf.lector_pdf/.MainActivity
timeout /t 12 /nobreak >nul
"%ADB%" -e shell uiautomator dump /sdcard/ui.xml >nul
"%ADB%" -e shell cat /sdcard/ui.xml > emu_ui0.xml
"%ADB%" -e shell input tap 1017 137
timeout /t 2 /nobreak >nul
"%ADB%" -e shell input tap 838 294
timeout /t 3 /nobreak >nul
"%ADB%" -e shell uiautomator dump /sdcard/ui.xml >nul
"%ADB%" -e shell cat /sdcard/ui.xml > emu_ui1.xml
echo HECHO
