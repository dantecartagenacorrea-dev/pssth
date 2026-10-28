import 'package:flutter/foundation.dart';

/// Medición en un equipo real: se activa al compilar con --dart-define=MEDIR=true.
const kMedir = bool.fromEnvironment('MEDIR');

/// Anota un tiempo en el registro (en pruebas o al medir; nunca en la app normal).
void perfLog(String message) {
  // ignore: avoid_print
  if (kDebugMode || kMedir) print('[lector] $message');
}
