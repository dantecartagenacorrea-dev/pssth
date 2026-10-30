import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Registro de errores que se queda en el aparato: nada se envía solo. La
/// persona lo comparte desde «Enviar informe de errores» si quiere.
class CrashLog {
  CrashLog._(this._dir);

  /// Carpeta donde se guarda (la de soporte de la app).
  final Future<Directory> _dir;

  static CrashLog? instance;

  /// Más que esto, se conserva solo la mitad más reciente.
  static const int maxBytes = 200 * 1024;

  /// Archivo de los errores de Dart y archivo que escribe Android cuando la
  /// parte nativa se cierra (MainActivity).
  static const fileName = 'errores.log';
  static const nativeFileName = 'errores_nativos.log';

  /// Engancha los errores de Flutter y los que quedan sin atrapar.
  static void install({Future<Directory>? dir}) {
    final log = CrashLog._(dir ?? getApplicationSupportDirectory());
    instance = log;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      log.record(details.exception, details.stack, where: details.library);
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      log.record(error, stack);
      return true;
    };
  }

  /// Para pruebas: un registro en [dir] sin tocar los manejadores globales.
  @visibleForTesting
  static CrashLog at(Directory dir) => CrashLog._(Future.value(dir));

  Future<void> _writing = Future.value();

  /// Anota un error (de a uno, sin perder ninguno si llegan seguidos).
  Future<void> record(Object error, StackTrace? stack, {String? where}) {
    final entry = format(error, stack, where: where, when: DateTime.now());
    final next = _writing.then((_) async {
      final file = File('${(await _dir).path}/$fileName');
      await file.writeAsString(entry, mode: FileMode.append, flush: true);
      if (await file.length() > maxBytes) {
        final text = await file.readAsString();
        await file.writeAsString(text.substring(text.length - maxBytes ~/ 2), flush: true);
      }
    });
    _writing = next.then((_) {}, onError: (_) {});
    return _writing;
  }

  /// Una entrada legible: fecha, plataforma, error y las primeras líneas de la
  /// pila (las que dicen dónde pasó).
  static String format(Object error, StackTrace? stack, {String? where, required DateTime when}) {
    final lines = (stack?.toString() ?? '').split('\n').where((l) => l.trim().isNotEmpty).take(25);
    return '=== ${when.toIso8601String()} · ${Platform.operatingSystem} ${Platform.operatingSystemVersion}'
        '${where == null ? '' : ' · $where'}\n'
        '$error\n${lines.join('\n')}\n\n';
  }

  /// Todo lo anotado (Dart y nativo), o '' si no hubo errores.
  Future<String> read() async {
    await _writing;
    final dir = await _dir;
    final b = StringBuffer();
    for (final name in [nativeFileName, fileName]) {
      final f = File('${dir.path}/$name');
      if (await f.exists()) b.write(await f.readAsString());
    }
    return b.toString();
  }

  Future<void> clear() async {
    await _writing;
    final dir = await _dir;
    for (final name in [nativeFileName, fileName]) {
      final f = File('${dir.path}/$name');
      if (await f.exists()) await f.delete();
    }
  }
}
