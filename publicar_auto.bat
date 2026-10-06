@echo off
cd /d "%~dp0"
git add -A
git -c user.name="Lector" -c user.email="lector@users.noreply.github.com" commit -m "Lector: OCR y deteccion de idioma en Android con ML Kit"
git push origin main
