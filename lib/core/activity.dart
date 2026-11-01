import 'package:flutter/foundation.dart';

/// Trabajos que la app hace en segundo plano (sincronizar, reconocer texto,
/// corregir con IA, bajar voces), para el indicador discreto de arriba.
class Activity {
  Activity._();

  /// Lo que está en curso, en el orden en que empezó (puede repetirse).
  static final current = ValueNotifier<List<String>>(const []);

  /// Hace [work] mostrando [label] mientras dura.
  static Future<T> run<T>(String label, Future<T> Function() work) async {
    current.value = [...current.value, label];
    try {
      return await work();
    } finally {
      final rest = List.of(current.value)..remove(label);
      current.value = rest;
    }
  }
}
