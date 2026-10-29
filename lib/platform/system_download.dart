import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Descargas grandes con el gestor de descargas de Android: siguen aunque la
/// app pase a segundo plano o se cierre, y se ven en la barra de
/// notificaciones. La descarga en curso se recuerda para retomarla al volver.
class SystemDownload {
  static const _channel = MethodChannel('lector/download');
  static String _key(String name) => 'descarga_$name';
  static String _pathKey(String name) => 'descarga_ruta_$name';

  /// Solo en Android (en iPhone la app descarga por su cuenta).
  static bool get available => Platform.isAndroid;

  /// ¿Hay una descarga de [name] empezada (quizá con la app cerrada)?
  static Future<bool> hasPending(String name) async {
    if (!available) return false;
    final p = await SharedPreferences.getInstance();
    return p.getInt(_key(name)) != null;
  }

  /// Descarga [url] como [name] y devuelve la ruta del archivo. Si ya había
  /// una descarga de [name] en curso o terminada, la retoma.
  static Future<File> fetch(
    String url,
    String name, {
    required String title,
    required int expectedBytes,
    void Function(double fraction)? onFraction,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getInt(_key(name));
    var path = prefs.getString(_pathKey(name));
    if (id != null) {
      final status = (await _query(id))['status'];
      if (status == 'missing' || status == 'failed') id = null;
    }
    if (id == null || path == null) {
      final r = await _channel.invokeMapMethod<String, Object>('enqueue', {'url': url, 'name': name, 'title': title});
      id = (r?['id'] as num?)?.toInt();
      path = r?['path'] as String?;
      if (id == null || path == null) throw const SocketException('No se pudo empezar la descarga.');
      await prefs.setInt(_key(name), id);
      await prefs.setString(_pathKey(name), path);
    }
    while (true) {
      final q = await _query(id);
      final done = (q['done'] as num?)?.toInt() ?? 0;
      final total = (q['total'] as num?)?.toInt() ?? -1;
      final size = total > 0 ? total : expectedBytes;
      if (size > 0) onFraction?.call((done / size).clamp(0, 1).toDouble());
      switch (q['status']) {
        case 'successful':
          return File(path);
        case 'failed' || 'missing':
          await forget(name);
          throw const SocketException('La descarga se interrumpió. Revisa la conexión e inténtalo de nuevo.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
  }

  /// Olvida la descarga de [name] y borra su archivo.
  static Future<void> forget(String name) async {
    if (!available) return;
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getInt(_key(name));
    if (id != null) {
      try {
        await _channel.invokeMethod<void>('remove', {'id': id});
      } on PlatformException {
        // ya no existía
      }
    }
    await prefs.remove(_key(name));
    await prefs.remove(_pathKey(name));
  }

  static Future<Map<String, Object?>> _query(int id) async =>
      await _channel.invokeMapMethod<String, Object?>('query', {'id': id}) ?? const {'status': 'missing'};
}
