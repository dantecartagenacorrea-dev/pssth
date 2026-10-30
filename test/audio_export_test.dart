import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/core/app_exception.dart';
import 'package:lector_pdf/data/wav_joiner.dart';
import 'package:lector_pdf/playback/range_audio_export.dart';

/// WAV PCM de 16 bits con [samples] muestras de valor [value] (y un fragmento
/// extra antes de los datos, como escriben algunas voces).
Uint8List wav(int samples, {int rate = 24000, int value = 7, bool extra = false}) {
  final list = BytesBuilder();
  ByteData u32(int v) => ByteData(4)..setUint32(0, v, Endian.little);
  ByteData u16(int v) => ByteData(2)..setUint16(0, v, Endian.little);
  void add(ByteData d) => list.add(d.buffer.asUint8List());
  final data = ByteData(samples * 2);
  for (var i = 0; i < samples; i++) {
    data.setInt16(i * 2, value, Endian.little);
  }
  final extraBytes = extra ? 8 + 4 : 0;
  list.add('RIFF'.codeUnits);
  add(u32(36 + extraBytes + samples * 2));
  list.add('WAVE'.codeUnits);
  list.add('fmt '.codeUnits);
  add(u32(16));
  add(u16(1));
  add(u16(1));
  add(u32(rate));
  add(u32(rate * 2));
  add(u16(2));
  add(u16(16));
  if (extra) {
    list.add('LIST'.codeUnits);
    add(u32(4));
    list.add('INFO'.codeUnits);
  }
  list.add('data'.codeUnits);
  add(u32(samples * 2));
  add(data);
  return list.toBytes();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('exportar'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('junta frases en trozos sin cortarlas', () {
    expect(exportPieces(['Uno.', 'Dos.', 'Tres.'], maxChars: 9), ['Uno. Dos.', 'Tres.']);
    expect(exportPieces([]), isEmpty);
    // Una frase más larga que el límite va sola, entera.
    expect(exportPieces(['Corta.', 'Una frase bastante larga.'], maxChars: 10), ['Corta.', 'Una frase bastante larga.']);
  });

  test('une WAV con cabeceras distintas en uno solo con los tamaños bien', () async {
    final joiner = WavJoiner('${dir.path}/todo.wav');
    await joiner.add(wav(100, value: 1));
    await joiner.add(wav(50, value: 2, extra: true));
    expect(await joiner.close(), isTrue);
    final out = File('${dir.path}/todo.wav').readAsBytesSync();
    final f = readWavFormat(out);
    expect((f.sampleRate, f.channels, f.bits, f.dataLength), (24000, 1, 16, 300));
    expect(out.length, 44 + 300);
    final b = ByteData.sublistView(out);
    expect(b.getUint32(4, Endian.little), 36 + 300);
    expect(b.getInt16(44 + 99 * 2, Endian.little), 1);
    expect(b.getInt16(44 + 100 * 2, Endian.little), 2);
  });

  test('si la voz cambia de formato a mitad, avisa', () async {
    final joiner = WavJoiner('${dir.path}/x.wav');
    await joiner.add(wav(10));
    expect(() => joiner.add(wav(10, rate: 22050)), throwsA(isA<AppException>()));
    await joiner.close();
  });

  test('exporta las frases trozo a trozo, avisa el avance y borra las partes', () async {
    final rendered = <String>[];
    final progress = <double>[];
    final path = await exportSentencesAudio(
      sentences: List.generate(5, (i) => 'Frase número $i del capítulo de prueba.' * 6),
      base: '${dir.path}/capitulo',
      render: (text, p) async {
        rendered.add(text);
        File(p).writeAsBytesSync(wav(10));
        return p;
      },
      onProgress: progress.add,
    );
    // Sin compresor (en pruebas no hay parte nativa) queda el WAV.
    expect(path, '${dir.path}/capitulo.wav');
    expect(readWavFormat(File(path!).readAsBytesSync()).dataLength, rendered.length * 20);
    expect(progress.last, 1.0);
    expect(dir.listSync().map((f) => f.uri.pathSegments.last), ['capitulo.wav']);
  });

  test('cancelar deja la carpeta limpia', () async {
    var calls = 0;
    final path = await exportSentencesAudio(
      sentences: List.generate(8, (i) => 'Frase $i. ' * 80),
      base: '${dir.path}/c',
      render: (text, p) async {
        calls++;
        File(p).writeAsBytesSync(wav(10));
        return p;
      },
      cancelled: () => calls >= 2,
    );
    expect(path, isNull);
    expect(calls, 2);
    expect(dir.listSync(), isEmpty);
  });

  test('una voz que no guarda audio da un mensaje claro', () async {
    await expectLater(
      exportSentencesAudio(sentences: ['Hola mundo.'], base: '${dir.path}/c', render: (_, _) async => null),
      throwsA(isA<AppException>()),
    );
    expect(dir.listSync(), isEmpty);
  });
}
