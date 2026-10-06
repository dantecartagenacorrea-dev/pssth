@echo off
set SDK=%LOCALAPPDATA%\Android\sdk
set ADB=%SDK%\platform-tools\adb.exe
set JAVA_HOME=%~dp0tool-jdk\jdk-17.0.20.1+1
set FL=%USERPROFILE%\flutter\bin\flutter.bat
echo %PATH% | findstr /i /c:"jdk-17.0.20.1+1\bin" >nul
if errorlevel 1 set PATH=%JAVA_HOME%\bin;%SDK%\platform-tools;%PATH%
