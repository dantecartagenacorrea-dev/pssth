import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/core/crash_log.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('errores'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('anota fecha, error y dónde pasó', () {
    final text = CrashLog.format(
      StateError('se rompió'),
      StackTrace.fromString('#0 main (a.dart:1)\n#1 otra (b.dart:2)'),
      where: 'widgets library',
      when: DateTime(2026, 10, 30, 5, 30),
    );
    expect(text, startsWith('=== 2026-10-30T05:30:00.000 · '));
    expect(text, contains('widgets library'));
    expect(text, contains('Bad state: se rompió'));
    expect(text, contains('#1 otra (b.dart:2)'));
  });

  test('junta los errores de Dart y los nativos, y se puede borrar', () async {
    final log = CrashLog.at(dir);
    expect(await log.read(), isEmpty);
    await log.record(Exception('uno'), null);
    await log.record(Exception('dos'), null);
    File('${dir.path}/${CrashLog.nativeFileName}').writeAsStringSync('=== nativo\nNullPointerException\n\n');
    final text = await log.read();
    expect(text.indexOf('NullPointerException'), lessThan(text.indexOf('uno')));
    expect(text.indexOf('uno'), lessThan(text.indexOf('dos')));
    await log.clear();
    expect(await log.read(), isEmpty);
  });

  test('no crece sin límite', () async {
    final log = CrashLog.at(dir);
    final big = 'x' * 5000;
    for (var i = 0; i < 60; i++) {
      await log.record(Exception('$i $big'), null);
    }
    final size = File('${dir.path}/${CrashLog.fileName}').lengthSync();
    expect(size, lessThanOrEqualTo(CrashLog.maxBytes));
    expect(await log.read(), contains('59 x'));
  });
}
