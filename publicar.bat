@echo off
cd /d "%~dp0"
where git >nul 2>nul || (echo Falta Git. Instala "Git for Windows" desde git-scm.com y vuelve a ejecutar. & pause & exit /b 1)
set URL=https://github.com/cartagenacorrealimitada-cell/lector.git
if not exist .git (git init -b main)
git add -A
git commit -m "Lector: version inicial"
git remote remove origin 2>nul
git remote add origin %URL%
echo.
echo Si se abre una ventana, inicia sesion en GitHub (hazlo tu).
git push -u origin main
echo.
echo Terminado. Puedes cerrar esta ventana.
pause
