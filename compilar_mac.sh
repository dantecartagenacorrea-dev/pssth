#!/bin/bash
# Ejecutar en el Mac, dentro de la carpeta del proyecto:  bash compilar_mac.sh
cd "$(dirname "$0")"
LOG=compilar_mac.log
{
  echo "=== $(date) ==="
  sw_vers; xcodebuild -version
  which flutter || echo "FALTA flutter"
  which pod || echo "FALTA cocoapods"
  flutter --version
  flutter pub get
  flutter analyze
  flutter test
  flutter build ios --release --no-codesign
  echo "=== FIN ==="
} 2>&1 | tee "$LOG"
