@echo off
cd /d "%~dp0"
set LOG=verificar.log
set FL=%USERPROFILE%\flutter\bin\flutter.bat
if not exist "%FL%" set FL=flutter
> %LOG% echo === %date% %time% ===
call "%FL%" --version >> %LOG% 2>&1
if not exist ios (
  >> %LOG% echo --- creando proyecto iOS ---
  call "%FL%" create --platforms=ios --org com.lectorpdf --project-name lector_pdf . >> %LOG% 2>&1
)
powershell -NoProfile -Command "$p='ios\Runner\Info.plist'; if (Test-Path $p) { $t=Get-Content $p -Raw; if ($t -notmatch 'UIBackgroundModes') { $t=$t -replace '</dict>\s*</plist>','<key>UIBackgroundModes</key><array><string>audio</string></array></dict></plist>'; Set-Content $p $t -NoNewline; 'Info.plist: audio en segundo plano agregado' } }" >> %LOG% 2>&1
call "%FL%" pub get >> %LOG% 2>&1
call "%FL%" analyze >> %LOG% 2>&1
call "%FL%" test >> %LOG% 2>&1
>> %LOG% echo === FIN ===
