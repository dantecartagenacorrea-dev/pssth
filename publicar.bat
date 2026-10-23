@echo off
cd /d "%~dp0"
set URL=https://github.com/dantecartagenacorrea-dev/lector.git
> publicar.log echo === publicar ===
git --version >> publicar.log 2>&1
git init >> publicar.log 2>&1
git branch -M main >> publicar.log 2>&1
git add -A >> publicar.log 2>&1
git -c user.name="Lector" -c user.email="lector@users.noreply.github.com" commit -m "Lector: EPUB, camara y fotos" >> publicar.log 2>&1
git remote remove origin >> publicar.log 2>&1
git remote add origin %URL% >> publicar.log 2>&1
echo Si se abre una ventana, inicia sesion en GitHub (hazlo tu).
git push -u origin main >> publicar.log 2>&1
type publicar.log
echo.
echo Terminado. Avisame.
pause
