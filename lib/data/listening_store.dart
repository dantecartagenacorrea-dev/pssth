import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/listening_stats.dart';

/// Cuánto se escuchó cada día, en un JSON local (nada sale del aparato).
class ListeningStore {
  ListeningStore(this._file);
  final File _file;
  final Map<String, DayListening> _days = {};
  Future<void>? _loading;

  /// La que usa la app (se crea al iniciar, como los subrayados).
  static ListeningStore? instance;

  /// Cambia con cada frase escuchada: la pantalla de estadísticas se actualiza.
  final ValueNotifier<int> changes = ValueNotifier(0);

  Future<void> _load() => _loading ??= _read();

  Future<void> _read() async {
    try {
      if (await _file.exists()) {
        final json = jsonDecode(await _file.readAsString());
        if (json is Map) {
          for (final e in json.entries) {
            if (e.value is Map) _days['${e.key}'] = DayListening.fromJson(Map<String, dynamic>.from(e.value as Map));
          }
        }
      }
    } catch (_) {
      _days.clear();
      // Se aparta el archivo dañado: el próximo guardado no lo pisa.
      try {
        await _file.rename('${_file.path}.dañado.${DateTime.now().millisecondsSinceEpoch}');
      } on FileSystemException {
        // no había archivo
      }
    }
  }

  /// De a uno y en un archivo aparte que se cambia de una vez (como los
  /// subrayados): dos frases seguidas no mezclan el JSON.
  Future<void> _save() {
    changes.value++;
    final next = _saving.then((_) async {
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode(_days.map((k, v) => MapEntry(k, v.toJson()))), flush: true);
      await tmp.rename(_file.path);
    });
    _saving = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _saving = Future.value();

  /// Suma lo escuchado al día de [at] (hoy si no se indica).
  Future<void> add({required int seconds, int words = 0, DateTime? at}) async {
    if (seconds <= 0 && words <= 0) return;
    await _load();
    final key = dayKey(at ?? DateTime.now());
    _days[key] = (_days[key] ?? const DayListening()).plus(seconds: seconds, words: words);
    await _save();
  }

  /// Lo escuchado en este aparato, por día (para sincronizar).
  Future<Map<String, DayListening>> days() async {
    await _load();
    return Map.unmodifiable(_days);
  }

  /// Lo escuchado en los otros aparatos (llega al sincronizar): se suma en la
  /// pantalla, pero no se guarda en el archivo de este aparato.
  Map<String, DayListening> _others = const {};

  void setOtherDevices(Map<String, DayListening> days) {
    _others = Map.unmodifiable(days);
    changes.value++;
  }

  Future<ListeningSummary> summary({DateTime? now}) async {
    await _load();
    final all = Map<String, DayListening>.of(_days);
    for (final e in _others.entries) {
      all[e.key] = (all[e.key] ?? const DayListening()).plus(seconds: e.value.seconds, words: e.value.words);
    }
    return summarizeListening(all, now ?? DateTime.now());
  }
}
