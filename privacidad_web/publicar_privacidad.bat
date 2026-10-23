@echo off
cd /d "%~dp0"
set URL=https://github.com/dantecartagenacorrea-dev/lector-privacidad.git
> publicar_privacidad.log echo === privacidad ===
git init >> publicar_privacidad.log 2>&1
git branch -M main >> publicar_privacidad.log 2>&1
git add index.html >> publicar_privacidad.log 2>&1
git -c user.name="Lector" -c user.email="lector@users.noreply.github.com" commit -m "Politica de privacidad de Lector" >> publicar_privacidad.log 2>&1
git remote remove origin >> publicar_privacidad.log 2>&1
git remote add origin %URL% >> publicar_privacidad.log 2>&1
git push -u origin main >> publicar_privacidad.log 2>&1
type publicar_privacidad.log
echo.
echo Terminado. Avisame.
pause
