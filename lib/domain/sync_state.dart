import 'dart:convert';

import 'listening_stats.dart';

/// Un dato que se sincroniza entre aparatos: su contenido en JSON (null si se
/// borró) y cuándo cambió por última vez, en milisegundos desde 1970.
class SyncRecord {
  const SyncRecord(this.time, this.data);

  final int time;
  final Object? data;

  bool get deleted => data == null;

  Map<String, dynamic> toJson() => {'t': time, 'd': data};

  factory SyncRecord.fromJson(Map<String, dynamic> j) => SyncRecord((j['t'] as num?)?.toInt() ?? 0, j['d']);
}

/// Todo lo que se comparte entre los aparatos de una persona. Cada dato va
/// con una clave estable en todos los aparatos (`doc:<huella>`, `bm:<id>`…).
class SyncState {
  const SyncState({this.records = const {}, this.listening = const {}});

  final Map<String, SyncRecord> records;

  /// Lo escuchado, aparte por aparato (aparato → día → escucha): cada uno
  /// anota lo suyo y la pantalla suma, así nada se cuenta dos veces.
  final Map<String, Map<String, DayListening>> listening;

  Map<String, dynamic> toJson() => {
    'v': 1,
    'records': {for (final e in records.entries) e.key: e.value.toJson()},
    'listening': {
      for (final d in listening.entries) d.key: {for (final e in d.value.entries) e.key: e.value.toJson()},
    },
  };

  /// Un archivo dañado o de otra forma da un estado vacío (no rompe nada:
  /// se vuelve a armar con lo de cada aparato).
  factory SyncState.fromJson(Map<String, dynamic> j) {
    final records = <String, SyncRecord>{};
    final listening = <String, Map<String, DayListening>>{};
    final rawRecords = j['records'];
    if (rawRecords is Map) {
      for (final e in rawRecords.entries) {
        if (e.value is Map) records['${e.key}'] = SyncRecord.fromJson(Map<String, dynamic>.from(e.value as Map));
      }
    }
    final rawListening = j['listening'];
    if (rawListening is Map) {
      for (final d in rawListening.entries) {
        if (d.value is! Map) continue;
        listening['${d.key}'] = {
          for (final e in (d.value as Map).entries)
            if (e.value is Map) '${e.key}': DayListening.fromJson(Map<String, dynamic>.from(e.value as Map)),
        };
      }
    }
    return SyncState(records: records, listening: listening);
  }
}

/// Compara lo que hay hoy en este aparato ([local]) con la última
/// sincronización: lo nuevo o cambiado lleva la hora [now]; lo que estaba
/// aquí ([lastLocalKeys]) y ya no está queda como borrado. Lo que solo existe
/// en otros aparatos no se toca. Si un dato sabe cuándo cambió de verdad
/// ([changedAt], como la última vez que se leyó un documento), se usa esa
/// hora en vez de [now].
SyncState observeLocal({
  required SyncState last,
  required Set<String> lastLocalKeys,
  required Map<String, Object?> local,
  required String device,
  required Map<String, DayListening> deviceListening,
  required int now,
  Map<String, int> changedAt = const {},
}) {
  final records = Map<String, SyncRecord>.of(last.records);
  for (final e in local.entries) {
    final before = last.records[e.key];
    final same = before != null && !before.deleted && _canonical(before.data) == _canonical(e.value);
    if (!same) records[e.key] = SyncRecord(changedAt[e.key] ?? now, e.value);
  }
  final docsHere = {
    for (final key in local.keys)
      if (key.startsWith('doc:')) key.substring(4),
  };
  for (final key in lastLocalKeys) {
    if (local.containsKey(key)) continue;
    final before = records[key];
    if (before == null || before.deleted) continue;
    // Quitar un documento de este aparato no toca los otros: ni el documento
    // ni sus marcadores y notas cuentan como borrados.
    final data = before.data;
    final doc = data is Map ? data['doc'] : null;
    if (key.startsWith('doc:') || (doc is String && !docsHere.contains(doc))) continue;
    records[key] = SyncRecord(now, null);
  }
  return SyncState(records: records, listening: {...last.listening, device: Map.of(deviceListening)});
}

/// Junta lo de dos aparatos. De cada dato gana el cambio más reciente (un
/// borrado también); la escucha de cada aparato se queda con lo más avanzado
/// de cada día. Da lo mismo el orden: los dos aparatos llegan al mismo estado.
SyncState mergeStates(SyncState a, SyncState b) {
  final records = Map<String, SyncRecord>.of(a.records);
  for (final e in b.records.entries) {
    final mine = records[e.key];
    if (mine == null || _wins(e.value, mine)) records[e.key] = e.value;
  }
  final listening = <String, Map<String, DayListening>>{for (final d in a.listening.entries) d.key: Map.of(d.value)};
  for (final d in b.listening.entries) {
    final days = listening.putIfAbsent(d.key, () => {});
    for (final e in d.value.entries) {
      final mine = days[e.key];
      if (mine == null || e.value.seconds > mine.seconds) days[e.key] = e.value;
    }
  }
  return SyncState(records: records, listening: listening);
}

/// La escucha de todos los aparatos sumada por día.
Map<String, DayListening> combinedListening(SyncState s) {
  final out = <String, DayListening>{};
  for (final days in s.listening.values) {
    for (final e in days.entries) {
      out[e.key] = (out[e.key] ?? const DayListening()).plus(seconds: e.value.seconds, words: e.value.words);
    }
  }
  return out;
}

/// ¿[x] le gana a [y]? El más reciente; con la misma hora, uno fijo (el de
/// texto mayor) para que todos los aparatos elijan igual.
bool _wins(SyncRecord x, SyncRecord y) {
  if (x.time != y.time) return x.time > y.time;
  return _canonical(x.data).compareTo(_canonical(y.data)) > 0;
}

/// JSON con las claves ordenadas: el mismo dato da el mismo texto aunque
/// las claves vengan en otro orden.
String _canonical(Object? v) => jsonEncode(_sorted(v));

Object? _sorted(Object? v) => switch (v) {
  Map() => {for (final k in (v.keys.map((k) => '$k').toList()..sort())) k: _sorted(v[k])},
  List() => [for (final x in v) _sorted(x)],
  _ => v,
};
