# Guía para publicar en Google Play, paso a paso

Para cuando Google apruebe la cuenta. Los textos y respuestas salen de [FICHA_GOOGLE_PLAY.md](FICHA_GOOGLE_PLAY.md).

## 0. Antes de empezar
- Cuenta verificada (identidad y teléfono).
- AAB listo: `build/app/outputs/bundle/release/app-release.aab` (1.0.0+5). Si se cambió código después del 08-11, recompilar: `flutter build appbundle --release`.
- Copia de la llave de subida guardada fuera de la PC (`android/upload-keystore.jks` y `android/key.properties`).

## 1. Crear la app
Play Console > **Crear aplicación**:
- Nombre: PSSTH!
- Idioma predeterminado: español (Latinoamérica), es-419
- App (no juego), gratuita
- Aceptar las declaraciones (lo hacés vos)

## 2. Configurar la app (panel «Configura tu app»)
| Sección | Qué poner |
|---|---|
| Política de privacidad | https://cartagenacorrealimitada-cell.github.io/pssth-privacidad/ |
| Acceso a la app | Toda la funcionalidad está disponible sin acceso especial |
| Anuncios | No contiene anuncios |
| Clasificación de contenido | Cuestionario IARC según la ficha (Utilidad/productividad, todo «no») |
| Público objetivo | 13+ (no dirigida a niños) |
| Seguridad de los datos | Según la ficha: Archivos y documentos, recopilados, no compartidos, opcionales, cifrados en tránsito |
| Apps gubernamentales / financieras / salud | No |
| Categoría | Productividad; correo y sitio de contacto |

## 3. Ficha de Play Store
Textos, ícono 512 px, imagen destacada 1024×500 y capturas de `tienda/play/`.

## 4. Prueba cerrada (obligatoria con cuenta personal)
1. Prueba > **Prueba cerrada** > crear pista (o usar «Alpha»).
2. Países: Bolivia (y los que quieras).
3. Verificadores: lista de correos con los 12 o más Gmail ([MENSAJE_EVALUADORES.md](MENSAJE_EVALUADORES.md)).
4. Crear versión > aceptar **Firma de apps de Play** > subir el AAB > notas de la versión > revisar > enviar a revisión.
5. Cuando la aprueben, copiar el **enlace para unirse** y mandar el mensaje 2 a los evaluadores.

## 5. Después de subir el AAB
- Configuración > Integridad de la app > **Firma de apps**: copiar la **SHA-1 de la clave de firma de apps** (la de Google, no la de subida).
- Google Cloud (proyecto pssth-514022) > Credenciales > crear cliente OAuth **Android** con `com.lectorpdf.lectorPdf` y esa SHA-1. Sin esto, «Sincronizar con Google Drive» falla en la app bajada de Play.
- Google Cloud > Google Auth Platform > Público > **Publicar app** (pasar de Prueba a Producción; drive.appdata no es sensible y no pide revisión). Mientras siga en Prueba, solo entran a Drive los correos cargados como usuarios de prueba (hasta 100). Ya hecho el 08-11: página principal, política y dominio autorizado en Marca; cliente iOS creado y puesto en `ios/Runner/Info.plist`.

## 6. Producción
A los 14 días con 12 verificadores activos aparece **Solicitar acceso a producción**: responder el cuestionario sobre la prueba (cuántos la usaron, qué se corrigió). Con la aprobación, promover la versión a Producción.
