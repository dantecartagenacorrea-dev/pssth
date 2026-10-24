<img src="assets/icon.png" width="80" align="left" style="margin-right:16px">

# PSSTH! (lector_pdf)

Convierte PDF, EPUB, imágenes, TXT y grabaciones en audio. Todo local, offline y sin coste: sin servidores, cuentas ni analítica.

## Arquitectura
- Flutter. PDF: pdfrx. Segundo plano / pantalla de bloqueo: audio_service.
- Voz: interfaz `TtsEngine` (`lib/playback/tts_engine.dart`) con dos motores. `AppleTtsEngine` (flutter_tts, voces del sistema) es el estable y el respaldo. `KokoroEngine` (Kokoro-82M int8 vía sherpa-onnx, voces Dora/Alex en español) es opcional: modelo descargado desde la app. `FallbackTtsEngine` une ambos: una sola lista de voces, la voz elegida decide el motor; si el neuronal falta, falla o va lento, vuelve solo al sistema sin cortar la lectura. Un bloque largo en otro idioma usa la voz del sistema para ese idioma y después vuelve.
- Audio neuronal: `AudioCache` (clave texto+motor+voz+velocidad, 200 MB, LRU, borrable) y `AudioPrefetcher` (prepara N+1 y N+2).
- Grabación de clases: `record` (WAV 16 kHz mono) → transcripción local: iOS `SFSpeechRecognizer` solo en el dispositivo (`SpeechBridge` en AppDelegate.swift); en cualquier plataforma Whisper base (sherpa-onnx, modelo opcional), por segmentos de ≤28 s cortados en silencio (`lib/domain/wav_audio.dart`). También acepta audios de otras apps (Abrir documento o Compartir).
- Modelos: `ModelStore` (`lib/data/model_store.dart`) descarga del repositorio oficial de sherpa-onnx (Apache 2.0), verifica SHA-256, extrae y borra lo sobrante. Pantalla "Voces y modelos" (menú ⋮ de la biblioteca). iOS 17+: botón para autorizar la Voz personal de Apple.
- Resumen extractivo local (`lib/domain/summarizer.dart`): frases clave del propio texto, sin IA.
- iOS nativo (`ios/Runner/AppDelegate.swift`): OCR con Vision, detección de idioma con NaturalLanguage, Voz personal, transcripción.
- Datos separados en la carpeta local de la app: archivo original (copia), texto extraído, caché OCR, progreso, marcadores, pronunciación, modelos (`models/`), caché de audio (temporal). Nada se envía fuera.

## Flujo
Importar → extraer texto (directo; OCR solo en páginas sin texto) → limpiar → normalizar para voz → detectar idioma (documento y por bloque) → fragmentar (párrafo → frase → cláusula) → reproducir (caché + pregeneración si es voz neuronal) → guardar progreso.

## Dependencias
pdfrx, flutter_tts, audio_service, file_picker, path_provider, shared_preferences, archive, image_picker, record, sherpa_onnx, just_audio, crypto. Todas open source, gratuitas, sin servicios externos. Modelos opcionales: Kokoro (132 MB) y Whisper base (208 MB, 160 MB instalado), ambos Apache 2.0.

## Pruebas
`verificar.bat` (Windows): pub get, analyze, test → `verificar.log`. Estado: 0 problemas de análisis, 88 pruebas OK. Probado en emulador Android: instalación de modelos desde la app, voz natural, transcripción Whisper de un audio en español, resumen, grabación.

## Pendiente
- Probar en iPhone (TestFlight): OCR Vision, pantalla bloqueada, Voz personal, transcripción nativa, rendimiento real de Kokoro (en emulador es lento).
- NLTokenizer nativo: descartado por ahora; el divisor en Dart ya trata abreviaturas y cláusulas y no se puede probar en iOS todavía.
- Documentos reales del usuario (escaneados, largos, dos columnas).
