import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/listening_stats.dart';
import 'package:lector_pdf/domain/sync_state.dart';

void main() {
  SyncState observe(
    SyncState last,
    Map<String, Object?> local, {
    Set<String>? lastLocal,
    int now = 100,
    String device = 'tablet',
    Map<String, DayListening> listening = const {},
  }) => observeLocal(
    last: last,
    lastLocalKeys: lastLocal ?? last.records.keys.toSet(),
    local: local,
    device: device,
    deviceListening: listening,
    now: now,
  );

  group('lo que cambió en este aparato', () {
    test('lo nuevo y lo cambiado llevan la hora de ahora; lo igual conserva la suya', () {
      final last = SyncState(
        records: {
          'doc:a': const SyncRecord(10, {'page': 3}),
          'doc:b': const SyncRecord(20, {'page': 7}),
        },
      );
      final s = observe(last, {
        'doc:a': {'page': 3},
        'doc:b': {'page': 8},
        'doc:c': {'page': 1},
      });
      expect(s.records['doc:a']!.time, 10);
      expect(s.records['doc:b']!.time, 100);
      expect(s.records['doc:c']!.time, 100);
    });

    test('el orden de las claves no cuenta como cambio', () {
      final last = SyncState(
        records: {
          'bm:1': const SyncRecord(10, {'a': 1, 'b': 2}),
        },
      );
      expect(
        observe(last, {
          'bm:1': {'b': 2, 'a': 1},
        }).records['bm:1']!.time,
        10,
      );
    });

    test('lo que estaba en este aparato y ya no está queda como borrado', () {
      final last = SyncState(
        records: {
          'bm:1': const SyncRecord(10, {'page': 2}),
        },
      );
      final r = observe(last, {}).records['bm:1']!;
      expect(r.deleted, isTrue);
      expect(r.time, 100);
    });

    test('lo que solo existe en otro aparato no se toca', () {
      final last = SyncState(
        records: {
          'bm:remoto': const SyncRecord(10, {'page': 2}),
        },
      );
      final r = observe(last, {}, lastLocal: {}).records['bm:remoto']!;
      expect(r.deleted, isFalse);
      expect(r.time, 10);
    });

    test('un borrado viejo sigue borrado', () {
      final last = SyncState(records: {'bm:1': const SyncRecord(10, null)});
      expect(observe(last, {}).records['bm:1']!.time, 10);
    });
  });

  group('mezcla de dos aparatos', () {
    test('gana el cambio más reciente', () {
      final tablet = SyncState(
        records: {
          'doc:a': const SyncRecord(50, {'page': 30}),
        },
      );
      final phone = SyncState(
        records: {
          'doc:a': const SyncRecord(80, {'page': 12}),
        },
      );
      expect(mergeStates(tablet, phone).records['doc:a']!.data, {'page': 12});
      expect(mergeStates(phone, tablet).records['doc:a']!.data, {'page': 12});
    });

    test('un borrado más reciente gana a una edición vieja, y al revés', () {
      final borrado = SyncState(records: {'bm:1': const SyncRecord(90, null)});
      final viejo = SyncState(
        records: {
          'bm:1': const SyncRecord(40, {'page': 2}),
        },
      );
      final nuevo = SyncState(
        records: {
          'bm:1': const SyncRecord(95, {'page': 2}),
        },
      );
      expect(mergeStates(borrado, viejo).records['bm:1']!.deleted, isTrue);
      expect(mergeStates(borrado, nuevo).records['bm:1']!.deleted, isFalse);
    });

    test('con la misma hora, la mezcla da lo mismo en los dos aparatos', () {
      final a = SyncState(records: {'pr:SQL': const SyncRecord(50, 'ese cu ele')});
      final b = SyncState(records: {'pr:SQL': const SyncRecord(50, 'sequel')});
      expect(mergeStates(a, b).records['pr:SQL']!.data, mergeStates(b, a).records['pr:SQL']!.data);
    });

    test('se juntan los datos que cada aparato tiene solo', () {
      final a = SyncState(
        records: {
          'bm:1': const SyncRecord(1, {'page': 1}),
        },
      );
      final b = SyncState(
        records: {
          'bm:2': const SyncRecord(2, {'page': 2}),
        },
      );
      expect(mergeStates(a, b).records.keys, containsAll(['bm:1', 'bm:2']));
    });

    test('la escucha de cada aparato se suma, sin contar dos veces', () {
      final tablet = observe(
        SyncState(),
        {},
        device: 'tablet',
        listening: {'2026-11-01': const DayListening(seconds: 600, words: 1000)},
      );
      final phone = observe(
        SyncState(),
        {},
        device: 'phone',
        listening: {'2026-11-01': const DayListening(seconds: 300, words: 400)},
      );
      final both = mergeStates(tablet, phone);
      // La tablet sincroniza otra vez lo mismo (ya escuchó más): no se duplica.
      final again = mergeStates(
        both,
        observe(both, {}, device: 'tablet', listening: {'2026-11-01': const DayListening(seconds: 700, words: 1200)}),
      );
      final day = combinedListening(again)['2026-11-01']!;
      expect(day.seconds, 1000);
      expect(day.words, 1600);
    });
  });

  test('se guarda y se vuelve a leer igual', () {
    final s = SyncState(
      records: {
        'doc:a': const SyncRecord(5, {'page': 3}),
        'bm:1': const SyncRecord(6, null),
      },
      listening: {
        'tablet': {'2026-11-01': const DayListening(seconds: 60, words: 10)},
      },
    );
    final again = SyncState.fromJson(jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);
    expect(again.records['doc:a']!.data, {'page': 3});
    expect(again.records['bm:1']!.deleted, isTrue);
    expect(again.listening['tablet']!['2026-11-01']!.seconds, 60);
    expect(SyncState.fromJson(const {'algo': 'roto'}).records, isEmpty);
  });
}
