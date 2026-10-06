import 'package:flutter/services.dart';

/// Archivo recibido desde otra app ("Abrir en Lector" / Compartir).
class OpenedFile {
  const OpenedFile({required this.path, required this.name});
  final String path;
  final String name;
}

/// Canal con el código nativo (iOS y Android) para archivos entrantes.
class OpenFileBridge {
  OpenFileBridge._();
  static final OpenFileBridge instance = OpenFileBridge._();

  static const _channel = MethodChannel('lector/open_file');
  void Function(OpenedFile file)? onOpened;

  void start() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'opened') {
        final f = _parse(call.arguments);
        if (f != null) onOpened?.call(f);
      }
    });
  }

  /// Archivo que llegó antes de que Flutter estuviera listo (arranque en frío).
  Future<OpenedFile?> takePending() async {
    try {
      return _parse(await _channel.invokeMethod<dynamic>('takePending'));
    } catch (_) {
      return null;
    }
  }

  OpenedFile? _parse(dynamic a) {
    if (a is! Map) return null;
    final path = a['path'];
    final name = a['name'];
    if (path is! String || path.isEmpty) return null;
    return OpenedFile(path: path, name: name is String && name.isNotEmpty ? name : 'documento');
  }
}
