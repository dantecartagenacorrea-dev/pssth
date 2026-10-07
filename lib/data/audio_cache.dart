import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Caché de audio sintetizado (solo para motores que generan audio).
/// Es temporal y se puede borrar sin perder documentos ni progreso.
class AudioCache {
  AudioCache(this.dir, {this.maxBytes = 200 * 1024 * 1024});

  final Directory dir;
  final int maxBytes;

  // Uso reciente en esta sesión (la fecha del archivo puede tener resolución de 1 s).
  final Map<String, int> _use = {};
  void _touch(String key) => _use[key] = DateTime.now().microsecondsSinceEpoch;

  // Operaciones de disco en serie: evita carreras entre prefetch y reproducción.
  Future<void> _lock = Future.value();
  Future<T> _serial<T>(Future<T> Function() op) {
    final next = _lock.then((_) => op());
    _lock = next.then((_) {}, onError: (_) {});
    return next;
  }

  /// Clave estable: texto + motor + voz + velocidad (+ extras relevantes).
  static String keyFor({
    required String text,
    required String engine,
    required String voice,
    required double speed,
    String extra = '',
  }) {
    final bytes = utf8.encode('$engine|$voice|${speed.toStringAsFixed(2)}|$extra|$text');
    // FNV-1a de 64 bits (sin dependencias) + longitud para reducir colisiones.
    var h = 0xcbf29ce484222325;
    for (final b in bytes) {
      h ^= b;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return '${h.toRadixString(16).padLeft(16, '0')}${bytes.length.toRadixString(16)}';
  }

  /// Archivo de la caché para [key] (existe solo tras un [put]).
  File fileFor(String key) => _file(key);

  /// ¿Hay audio válido guardado? Lo marca como usado.
  Future<bool> has(String key) => _serial(() async {
        try {
          final f = _file(key);
          if (!await f.exists() || await f.length() == 0) return false;
          _touch(key);
          return true;
        } catch (_) {
          return false;
        }
      });

  File _file(String key) => File('${dir.path}${Platform.pathSeparator}$key.wav');

  Future<Uint8List?> get(String key) => _serial(() => _get(key));

  Future<Uint8List?> _get(String key) async {
    try {
      final f = _file(key);
      if (!await f.exists()) return null;
      final data = await f.readAsBytes();
      if (data.isEmpty) return null;
      _touch(key);
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<void> put(String key, Uint8List data) => _serial(() => _put(key, data));

  Future<void> _put(String key, Uint8List data) async {
    if (data.isEmpty) return;
    await dir.create(recursive: true);
    final tmp = File('${_file(key).path}.tmp');
    await tmp.writeAsBytes(data, flush: true);
    await tmp.rename(_file(key).path);
    _touch(key);
    await _trim();
  }

  Future<int> sizeBytes() async {
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  /// Elimina primero lo menos usado hasta quedar por debajo de [maxBytes].
  Future<void> trim() => _serial(_trim);

  Future<void> _trim() async {
    if (!await dir.exists()) return;
    final files = <(File, int, DateTime)>[];
    var total = 0;
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.wav')) {
        try {
          final st = await e.stat();
          total += st.size;
          final name = e.uri.pathSegments.last;
          final key = name.substring(0, name.length - 4);
          files.add((e, st.size, DateTime.fromMicrosecondsSinceEpoch(_use[key] ?? st.modified.microsecondsSinceEpoch)));
        } catch (_) {}
      }
    }
    if (total <= maxBytes) return;
    files.sort((a, b) => a.$3.compareTo(b.$3));
    for (final f in files) {
      if (total <= maxBytes) break;
      try {
        await f.$1.delete();
        total -= f.$2;
      } catch (_) {}
    }
  }

  Future<void> clear() => _serial(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
}
