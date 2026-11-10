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
- Formulario lleno, imagen chica (497×722): En limpio con la tabla completa
  (bordes y divisiones), sin rayas falsas sobre el texto. Las líneas grises de
  1 píxel se encuentran sumando dos filas vecinas (`_lineInkOf`), salvo dentro
  de los renglones leídos.
- Dígitos: letras parecidas dentro de números (o→0, l→1, s→5) se corrigen
  (`lib/domain/ocr_fixes.dart`): «+591 7oooO00» sale «+591 70000000».

## Probado y descartado

- Agrandar fotos chicas antes de leerlas: el título salió como imagen y la
  letra a mano quedó partida. Revertido.
- Corregir palabras con el diccionario en En limpio: cambió «pido» por
  «pirulo» sin aviso. Revertido; el diccionario queda solo en la revisión,
  donde la corrección se ve en naranja.
- Suavizar la imagen contra el muaré: borra también las líneas finas.

## Lo que falta (no es 100/100)

- **Errores de lectura de la cámara** (ML Kit Text Recognition): letras
  confundidas («PRESCNTA», «1485» por 1985). Se corrigen en la revisión antes
  de guardar (renglones en naranja).
- **Casillas**: las de fecha no se cierran (sus lados son más cortos que
  `_minVertical`), y la casilla ☐ pegada a una palabra hace leer «Daster» por
  «Master».
- **Foto de una pantalla** (muaré): Escaneado bien; En limpio mejorable.
- Las vistas Original y En limpio no se sincronizan con Drive.
- No probado en iPhone. `.github/workflows/ios.yml` tiene reintentos de
  SwiftPM sin probar.

## Cómo probar

```bash
flutter analyze
flutter test
flutter build apk --release --split-per-abi --target-platform android-arm64
```

728 pruebas pasan. `test/playback_loop_test.dart` fallaba a veces en la corrida
completa por falta de tiempo de espera; ahora espera hasta 15 s y pasó en todas
las corridas.
