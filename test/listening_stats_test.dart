import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/data/listening_store.dart';
import 'package:lector_pdf/domain/listening_stats.dart';

void main() {
  final now = DateTime(2026, 11, 1, 22, 30);

  test('suma hoy, la semana y el total', () {
    final s = summarizeListening({
      '2026-11-01': const DayListening(seconds: 600, words: 1500),
      '2026-10-28': const DayListening(seconds: 300, words: 700),
      '2026-10-01': const DayListening(seconds: 1200, words: 3000),
    }, now);
    expect(s.today.seconds, 600);
    expect(s.week.seconds, 900);
    expect(s.total.seconds, 2100);
    expect(s.total.words, 5200);
    expect(s.lastDays.length, 7);
    expect(s.lastDays.last.$1, DateTime(2026, 11, 1));
    expect(s.lastDays.first.$1, DateTime(2026, 10, 26));
  });

  test('la racha cuenta días seguidos con al menos un minuto', () {
    final s = summarizeListening({
      '2026-11-01': const DayListening(seconds: 90),
      '2026-10-31': const DayListening(seconds: 60),
      '2026-10-30': const DayListening(seconds: 30), // menos de un minuto: corta
      '2026-10-29': const DayListening(seconds: 900),
    }, now);
    expect(s.streak, 2);
  });

  test('si hoy todavía no se escuchó, la racha sigue desde ayer', () {
    final s = summarizeListening({
      '2026-10-31': const DayListening(seconds: 120),
      '2026-10-30': const DayListening(seconds: 120),
    }, now);
    expect(s.streak, 2);
    expect(summarizeListening({}, now).streak, 0);
  });

  test('formato del tiempo', () {
    expect(listeningTime(0), '0 min');
    expect(listeningTime(30), 'menos de 1 min');
    expect(listeningTime(12 * 60 + 5), '12 min');
    expect(listeningTime(65 * 60), '1 h 05 min');
  });

  test('guarda lo escuchado y lo vuelve a leer', () async {
    final dir = Directory.systemTemp.createTempSync('escucha');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/listening.json');
    final store = ListeningStore(file);
    await store.add(seconds: 30, words: 80, at: now);
    await store.add(seconds: 45, words: 100, at: now);
    final again = await ListeningStore(file).summary(now: now);
    expect(again.today.seconds, 75);
    expect(again.today.words, 180);
  });

  test('un archivo dañado no impide seguir anotando', () async {
    final dir = Directory.systemTemp.createTempSync('escucha');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/listening.json')..writeAsStringSync('{roto');
    final store = ListeningStore(file);
    await store.add(seconds: 60, at: now);
    expect((await ListeningStore(file).summary(now: now)).today.seconds, 60);
  });
}
