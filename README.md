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
- Corrección avanzada opcional (`lib/services/llm_cleaner.dart`): apagada por defecto. Si el usuario la activa (menú de la biblioteca → "Corrección avanzada (IA local)") y da la URL de un servidor Ollama en su red, el texto de cada página se envía por http a ese servidor para corregirlo. Si no responde, se lee el texto original. Es la única salida de datos del dispositivo, y va solo a la dirección que configura el usuario. iOS pide permiso de red local (`NSLocalNetworkUsageDescription`). Android no necesita configuración: `dart:io` no aplica la política de texto en claro.
- iOS nativo (`ios/Runner/AppDelegate.swift`): OCR con Vision, detección de idioma con NaturalLanguage, Voz personal, transcripción.
- Datos separados en la carpeta local de la app: archivo original (copia), texto extraído, caché OCR, progreso, marcadores, pronunciación, modelos (`models/`), caché de audio (temporal). Nada se envía fuera, salvo la corrección opcional con Ollama.

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

### Antes de publicar en App Store (revisión legal, 26-10-2026; aplicar en conjunto)
**1. Licencia.** ✅ Resuelto el 26-10-2026 (PR #2): `sherpa_onnx` 2.0.1 sin espeak-ng, verificado en las librerías nativas de la APK de Android y en `SherpaOnnxC.framework` de iOS (0 firmas de espeak-ng; la 1.13.8 tenía 5). Se eligió la opción (a): conversor propio `lib/domain/spanish_phonemizer.dart` (seseo por defecto) más `lib/domain/spanish_numbers.dart`, aprobado a oído en PC. Falta escucharlo en el iPhone. Los modelos ya instalados conservan una carpeta `espeak-ng-data` que no se usa; las instalaciones nuevas la borran. Detalle original:

`sherpa_onnx` 1.13.8 lleva espeak-ng (GPL-3.0-or-later) compilado dentro de las librerías nativas de Android e iOS. Verificado en los binarios y reconocido por el proyecto (k2-fsa/sherpa-onnx#3731 y #4053). No publicar con esta versión.
- Actualizar a `sherpa_onnx` 2.0.0 (23-10-2026), que ya no incluye espeak-ng (PR #4055).
- `kokoro_worker.dart`: `maxNumSenetences` pasa a ser `maxNumSentences` (si no, no compila). Quitar `dataDir` (en la 2.0 se ignora).
- `model_store.dart`: quitar `espeak-ng-data` de `requiredFiles`. Actualizar el comentario de `kokoro_engine.dart`.
- Whisper (`whisper_transcriber.dart`): sin cambios de API.
- **Decisión (tomada: opción a), voces Kokoro en español (Dora/Alex).** En la 2.0 no hay léxico español oficial, y Kokoro se salta sin avisar las palabras que no están en el léxico. Solo con actualizar, el español dejaría de sonar bien. Opciones:
  - (a) Conversor propio texto→fonemas IPA en español, en Dart y sin GPL, pasado como `phonemeCodepoints` en `generateWithConfig`. Hay que imitar la salida de espeak `es` y probar la calidad escuchando.
  - (b) Quitar Kokoro para español y dejar solo las voces del sistema.
  - No usar `piper_phonemize`: también es GPL.

**2. Privacidad y ficha de la tienda.** ✅ Hecho el 26-10-2026: política (web y `tienda/PRIVACIDAD.md`) y ficha ya cubren grabación, transcripción, copias de audios recibidos, descarga de modelos desde GitHub y el "sin Internet" corregido. El aviso de consentimiento ya estaba en la pantalla de grabación. Detalle original:
- `privacidad_web/index.html` y `tienda/PRIVACIDAD.md` deben explicar:
  - Micrófono y grabación: el audio se guarda en el dispositivo junto al documento y "Eliminar" lo borra.
  - Transcripción local: iOS con reconocimiento obligatorio en el dispositivo; si no, Whisper local, sin enviar audio fuera.
  - Audios recibidos de otras apps: se guarda una copia.
  - Descarga opcional de modelos desde GitHub: es una conexión a Internet, y GitHub ve la IP.
- `tienda/FICHA_APP_STORE.md`: corregir "Sin Internet" (las descargas de modelos son opcionales). Añadir grabación y transcripción a la descripción, los textos de micrófono y reconocimiento de voz a "Texto de los permisos", y una mención en las notas para la revisión.
- Aviso al grabar: recordar que grabar a otras personas puede requerir su consentimiento (en la pantalla de grabación y en la política).

**3. Coherencia de nombre y créditos.** ✅ Hecho el 26-10-2026 (textos de permisos, menú y "Acerca de" con créditos de Kokoro, Whisper, sherpa-onnx y espeak-ng mientras siga incluido), salvo la marca. Detalle original:
- `ios/Runner/Info.plist`: los textos de cámara, fotos, micrófono y reconocimiento de voz dicen "Lector"; cambiarlos a "PSSTH!". El menú dice "Acerca de Lector y licencias".
- Créditos de modelos en "Acerca de" / "Voces y modelos": Kokoro-82M (Apache 2.0; entrenado con datos CC BY: Koniwa y SIWIS) y Whisper (MIT). Hoy solo dice "sherpa-onnx (Apache 2.0)", y eso solo será cierto tras actualizar a la 2.0.
- Sin comprobar: si la marca "PSSTH!" está registrada por terceros.
