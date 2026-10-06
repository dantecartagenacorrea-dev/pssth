# Lector (lector_pdf)

Convierte PDF, imágenes y TXT en audio. Todo local, offline y sin coste: sin servidores, cuentas ni analítica.

## Arquitectura
- Flutter. PDF: pdfrx. Voz: flutter_tts (voces del sistema). Segundo plano / pantalla de bloqueo: audio_service.
- iOS nativo (en `ios/Runner/AppDelegate.swift`): OCR con Vision y detección de idioma con NaturalLanguage, vía canal `lector/native_text`.
- Datos separados en la carpeta local de la app: archivo original (copia), texto extraído (`*.text.json`), caché OCR (`*.ocr.json`), progreso (`library.json`), marcadores, pronunciación. El texto normalizado para voz se calcula al abrir y nunca se guarda sobre el original.

## Flujo
Importar → extraer texto (directo; OCR solo en páginas sin texto) → limpiar (encabezados, pies, guiones) → normalizar para voz (Art., Bs, %, diccionario) → detectar idioma/voz → reproducir → guardar progreso.

## Dependencias
pdfrx, flutter_tts, audio_service, file_picker, path_provider, shared_preferences (todas open source, gratuitas, sin servicios externos).

## Pruebas
`verificar.bat` (Windows): pub get, analyze, test → `verificar.log`. Estado: 0 problemas de análisis, 38 pruebas OK.

## Pendiente
- Compilar y probar en iPhone (requiere macOS: `.github/workflows/ios.yml` o un Mac). El código Swift y los canales nativos aún no se han compilado.
- Recibir archivos desde la hoja Compartir de iOS; cámara/escáner; EPUB; orden de lectura en columnas; iPad/macOS.
