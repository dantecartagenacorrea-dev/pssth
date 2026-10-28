import 'package:flutter/services.dart';

import '../core/app_exception.dart';

/// Escáner de documentos del sistema: VisionKit en iPhone/iPad y el de Google
/// (ML Kit, vía Play Services) en Android. Detecta los bordes, endereza y
/// permite varias páginas. Todo en el dispositivo.
class DocumentScanner {
  static const _channel = MethodChannel('lector/scan');

  /// Rutas de las páginas escaneadas (JPEG), en orden. Vacío si se canceló.
  Future<List<String>> scan() async {
    try {
      final paths = await _channel.invokeMethod<List<Object?>>('scan');
      return (paths ?? const []).whereType<String>().toList();
    } on MissingPluginException {
      throw AppException('El escáner de documentos no está disponible en este equipo.');
    } on PlatformException catch (e) {
      throw AppException(e.message ?? 'No se pudo abrir el escáner de documentos.');
    }
  }
}
