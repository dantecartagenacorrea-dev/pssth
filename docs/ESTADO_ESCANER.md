# Estado del escáner (9 de noviembre de 2026)

Documento de traspaso: qué hace el escáner de PSSTH, qué está verificado en un
dispositivo real y qué falta. Todo lo de abajo está en este commit.

## Flujo

1. **Escanear** abre el escáner de Google (ML Kit, `SCANNER_MODE_FULL`):
   recorta la hoja y quita sombras, manchas y dedos.
   `android/app/src/main/kotlin/com/lectorpdf/lector_pdf/MainActivity.kt`.
2. **Hoja arrugada** (solo Android) usa la cámara y aplana la hoja con UVDoc
   (modelo ONNX que se baja una vez). `lib/ui/library_screen.dart`, `_scanWrinkled`.
3. **Revisión** (`lib/ui/scan_review_screen.dart`): empieza en «Original» (lo que
   entregó el escáner, sin filtro). Cada filtro se compara con la foto
   (`contentKept` en `lib/domain/scan_filters.dart`). Si conserva menos del 90 %
   del contenido o de las líneas rectas, el filtro sale apagado con «Borra datos»
   y nunca se guarda.
4. Cada documento (escaneo, foto o PDF) tiene tres vistas junto a
   Buscar/Resumen/Preguntas: **Original**, **Escaneado** y **En limpio**
   (`lib/ui/scan_versions_screen.dart`, `lib/data/scan_version_builder.dart`).
   Se arman al primer toque y quedan guardadas junto al documento.
5. **En limpio** reescribe la hoja con el formato original
   (`lib/domain/form_page.dart`): texto leído en su lugar, mismo cuerpo de letra,
   renglones justificados, negritas, líneas de formulario redibujadas rectas y
   lo demás (casillas, firmas, letra a mano) como imagen en su sitio.

## Verificado en una tablet Android real

- Documento impreso y arrugado de 2 páginas: Original, Escaneado y En limpio
  correctos, sin rayas falsas ni sombras de borde.
- Formulario lleno a mano (foto de pantalla): Escaneado completo, con tabla,
  casillas y letra a mano.
- El filtro «Limpio» se apaga en formularios porque borra tablas grises.

## Lo que falta (no es 100/100)

- **En limpio en formularios con tabla**: faltan bordes y divisiones internas
  de algunas tablas. La detección de líneas está en `formLayerFrom` y
  `_dropTexture` (`lib/domain/form_page.dart`); con muaré de pantalla se
  descartan también líneas reales.
- **Errores de lectura de la cámara** (ML Kit Text Recognition): letras
  confundidas y mayúsculas mezcladas. La revisión los marca en naranja para
  corregirlos antes de guardar; no hay corrección automática.
- **Foto de una pantalla** (muaré): Escaneado bien; En limpio mejorable.
- Las vistas Original y En limpio no se sincronizan con Drive.
- `test/playback_loop_test.dart` falló 2 veces en ~10 corridas completas
  (temporizador); pasa siempre sola. No investigado.
- No probado en iPhone. `.github/workflows/ios.yml` tiene reintentos de
  SwiftPM sin probar.

## Cómo probar

```bash
flutter analyze
flutter test
flutter build apk --release --split-per-abi --target-platform android-arm64
```

720 pruebas pasan. El AAB anterior para Play (commit 79f4c8f) no incluye nada de esto.
