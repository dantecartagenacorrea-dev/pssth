@echo off
set SDK=%LOCALAPPDATA%\Android\sdk
set ADB=%SDK%\platform-tools\adb.exe
rem JDK propio si existe; si no, el JAVA_HOME del sistema.
if exist "%~dp0tool-jdk\jdk-17.0.20.1+1" set JAVA_HOME=%~dp0tool-jdk\jdk-17.0.20.1+1
set FL=%USERPROFILE%\flutter\bin\flutter.bat
echo %PATH% | findstr /i /c:"jdk-17.0.20.1+1\bin" >nul
if errorlevel 1 set PATH=%JAVA_HOME%\bin;%SDK%\platform-tools;%PATH%
