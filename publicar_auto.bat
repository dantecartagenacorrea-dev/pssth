@echo off
cd /d "%~dp0"
git add -A
git -c user.name="Lector" -c user.email="lector@users.noreply.github.com" commit -m "Lector: fase 1 y 2 (abrir desde otras apps, columnas, correcciones)"
git push origin main
