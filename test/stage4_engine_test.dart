import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/data/audio_cache.dart';
import 'package:lector_pdf/domain/chunker.dart';
import 'package:lector_pdf/domain/language_segmenter.dart';
import 'package:lector_pdf/playback/audio_prefetcher.dart';

class _Synth extends SynthesizingEngine {
  int calls = 0;
  @override
  String get id => 'fake';
  @override
  Future<Uint8List> synthesize(String text) async {
    calls++;
    return Uint8List.fromList(text.codeUnits.map((c) => c & 0xFF).toList());
  }
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('audiocache'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('clave depende de texto, motor, voz y velocidad', () {
    String k({String t = 'hola', String e = 'a', String v = 'x', double s = 1}) =>
        AudioCache.keyFor(text: t, engine: e, voice: v, speed: s);
    expect(k(), k());
    expect({k(), k(t: 'hola!'), k(e: 'b'), k(v: 'y'), k(s: 1.25)}.length, 5);
  });

  test('caché: guarda, lee, recorta lo menos usado y se puede borrar', () async {
    final c = AudioCache(tmp, maxBytes: 250);
    await c.put('a', Uint8List(100));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await c.put('b', Uint8List(100));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(await c.get('a'), isNotNull); // 'a' pasa a ser el más reciente
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await c.put('c', Uint8List(100)); // 300 > 250: cae 'b'
    expect(await c.get('b'), isNull);
    expect(await c.get('a'), isNotNull);
    expect(await c.get('c'), isNotNull);
    await c.clear();
    expect(await c.sizeBytes(), 0);
  });

  test('prefetcher: reproduce desde caché y no sintetiza dos veces', () async {
    final s = _Synth();
    final p = AudioPrefetcher(engine: s, cache: AudioCache(tmp), voice: 'v', speed: 1);
    final chunks = ['uno', 'dos', 'tres', 'cuatro'];
    p.prefetch(chunks, 0); // prepara 'dos' y 'tres'
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(s.calls, 2);
    await p.fileFor('dos');
    await p.fileFor('tres');
    expect(s.calls, 2);
    await p.fileFor('cuatro');
    expect(s.calls, 3);
  });

  test('idioma: una frase corta extranjera no cambia la voz', () {
    final langs = segmentLanguages(
      [
        'El libro cuenta la historia de una familia que vive en el campo con sus animales y su tierra.',
        'Hello world.',
        'La casa estaba en el centro del pueblo y todos los vecinos conocían a sus dueños desde hacía años.',
      ],
      documentLanguage: 'es',
    );
    expect(langs, ['es', 'es', 'es']);
  });

  test('idioma: un bloque largo en inglés sí cambia', () {
    final langs = segmentLanguages(
      [
        'La casa estaba en el centro del pueblo y todos los vecinos conocían a sus dueños.',
        'The house was in the middle of the town and all of the neighbors knew the owners from the years that they had lived there.',
      ],
      documentLanguage: 'es',
    );
    expect(langs, ['es', 'en']);
  });

  test('fragmentación: prefiere cortar en coma/punto y coma', () {
    final long = '${'palabra ' * 30}uno, ${'texto ' * 25}dos; ${'otra ' * 40}fin.';
    final parts = splitPageText(long, maxLength: 400);
    for (final p in parts) {
      expect(p.length <= 400, isTrue);
    }
    expect(parts.length, greaterThan(1));
    expect(parts.first.endsWith(',') || parts.first.endsWith(';') || parts.first.endsWith(':'), isTrue);
    expect(parts.join(' ').replaceAll(RegExp(r'\s+'), ' '), long.replaceAll(RegExp(r'\s+'), ' ').trim());
  });
}
