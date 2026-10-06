@echo off
cd /d "%~dp0"
git add -A
git -c user.name="Lector" -c user.email="lector@users.noreply.github.com" commit -m "Lector: mejor voz automatica, lectura de fechas-romanos-siglas, acerca de"
git push origin main
