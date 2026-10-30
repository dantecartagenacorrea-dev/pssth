import 'dart:io';

/// Restos de la IA de la tablet (Qwen3) que el motor dejó en la caché: más de
/// 600 MB que nadie vuelve a usar desde que se quitó.
const _retiredPrefixes = ['qwen3'];

/// Temporales propios que ya cumplieron su trabajo: lo exportado o escaneado
/// se compartió o quedó en la biblioteca, lo elegido con el selector de
/// archivos ya se copió. Se guardan un día por si la app que los recibió
/// todavía los está leyendo.
const _tempPrefixes = [
  'audio_exportado',
  'escaneos',
  'escaneo',
  'file_picker',
  'grabacion_',
  'scaled_',
  'PSSTH-errores',
  'lector_fragmento_',
  'Resumen_',
];

const _keepFor = Duration(days: 1);

/// Limpia la carpeta temporal de la app: lo retirado siempre y los
/// temporales propios de más de un día. No toca la caché de audio ni lo que
/// guardan otras bibliotecas. Devuelve los bytes liberados.
Future<int> cleanTemporary(Directory dir, {DateTime? now}) async {
  if (!await dir.exists()) return 0;
  final limit = (now ?? DateTime.now()).subtract(_keepFor);
  var freed = 0;
  await for (final e in dir.list(followLinks: false)) {
    final name = e.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    final retired = _retiredPrefixes.any(name.startsWith);
    final temp = _tempPrefixes.any(name.startsWith) || name.endsWith('(editado).pdf');
    if (!retired && !temp) continue;
    try {
      if (!retired && (await e.stat()).modified.isAfter(limit)) continue;
      freed += await _size(e);
      await e.delete(recursive: true);
    } on FileSystemException {
      // en uso o ya borrado: se intenta la próxima vez
    }
  }
  return freed;
}

Future<int> _size(FileSystemEntity e) async {
  if (e is File) return e.length();
  if (e is! Directory) return 0;
  var total = 0;
  await for (final f in e.list(recursive: true, followLinks: false)) {
    if (f is File) total += await f.length();
  }
  return total;
}
