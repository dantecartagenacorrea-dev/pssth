import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/data/library_store.dart';
import 'package:lector_pdf/core/motion.dart';
import 'package:lector_pdf/data/settings_store.dart';
import 'package:lector_pdf/domain/chapter_detector.dart';
import 'package:lector_pdf/domain/library_entry.dart';
import 'package:lector_pdf/domain/text_chunk.dart';
import 'package:lector_pdf/playback/tts_audio_handler.dart';
import 'package:lector_pdf/playback/tts_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Motor de prueba: cada frase queda "sonando" hasta que la prueba la termina,
/// y puede fallar las que se le indiquen.
class SlowEngine extends TtsEngine {
  final spoken = <String>[];
  final pending = <Completer<void>>[];
  final failing = <String>{};
  @override
  String get id => 'slow';
  @override
  Future<void> init() async {}
  @override
  Future<List<VoiceOption>> voices() async => const [];
  @override
  Future<void> setVoice(VoiceOption voice) async {}
  @override
  Future<void> setLanguage(String locale) async {}
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> speak(String text) {
    spoken.add(text);
    if (failing.contains(text)) {
      onError?.call('falló $text');
      return Future.value();
    }
    final c = Completer<void>();
    pending.add(c);
    return c.future;
  }

  /// Termina la frase que está sonando.
  void finishCurrent() => pending.removeAt(0).complete();

  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

Future<(TtsAudioHandler, Directory)> handlerWith(
  SlowEngine engine,
  List<String> texts, {
  bool onePerPage = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final tmp = Directory.systemTemp.createTempSync('lib');
  final store = LibraryStore();
  await store.initAt(tmp);
  final h = TtsAudioHandler(libraryStore: store, settingsStore: SettingsStore(), engine: engine);
  await h.setup();
  final entry = LibraryEntry(id: 'd', name: 'd.txt', storedPath: '', pageCount: 1, totalChunks: texts.length);
  await store.upsert(entry);
  await h.loadDocument(
    entry: entry,
    chunks: [
      for (var i = 0; i < texts.length; i++)
        TextChunk(documentId: 'd', pageIndex: onePerPage ? i : 0, chunkIndex: onePerPage ? 0 : i, text: texts[i]),
    ],
  );
  return (h, tmp);
}

// Con margen: en la corrida completa (varios archivos a la vez) 20 ms no alcanzaban.
Future<void> settle() => Future.delayed(const Duration(milliseconds: 100));

/// Espera (hasta 15 s) a que se cumpla [done]: guardar la posición toca el
/// disco y, con todas las pruebas corriendo a la vez (las del escáner procesan
/// imágenes grandes), 4 s a veces no alcanzaban. Si se cumple antes, sigue al
/// instante.
Future<void> until(bool Function() done) async {
  for (var i = 0; i < 150 && !done(); i++) {
    await settle();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pausar y reanudar rápido no deja dos lecturas a la par', () async {
    final engine = SlowEngine();
    final (h, tmp) = await handlerWith(engine, ['Uno.', 'Dos.', 'Tres.']);
    unawaited(h.play());
    await until(() => engine.pending.length == 1);
    await h.pause();
    unawaited(h.play()); // reanuda antes de que la frase anterior termine
    await until(() => engine.spoken.length == 2);
    // Termina la frase vieja (la del bucle pausado): no debe avanzar por su cuenta.
    engine.finishCurrent();
    await settle();
    expect(engine.spoken, ['Uno.', 'Uno.']);
    engine.finishCurrent(); // termina la frase del bucle vigente
    await until(() => engine.spoken.length == 3);
    expect(engine.spoken, ['Uno.', 'Uno.', 'Dos.']);
    expect(h.chunkIndex, 1);
    await h.stop();
    tmp.deleteSync(recursive: true);
  });

  test('una frase que falla se salta y la lectura sigue', () async {
    final engine = SlowEngine()..failing.add('Dos.');
    final (h, tmp) = await handlerWith(engine, ['Uno.', 'Dos.', 'Tres.']);
    unawaited(h.play());
    await until(() => engine.pending.length == 1);
    engine.finishCurrent(); // Uno.
    await until(() => engine.spoken.length == 3);
    expect(engine.spoken, ['Uno.', 'Dos.', 'Tres.']);
    expect(h.snapshot.value.message, isNull);
    engine.finishCurrent(); // Tres.
    await until(() => !h.snapshot.value.playing);
    tmp.deleteSync(recursive: true);
  });

  test('si fallan varias frases seguidas, se detiene y avisa', () async {
    final engine = SlowEngine()..failing.addAll(['A.', 'B.', 'C.']);
    final (h, tmp) = await handlerWith(engine, ['A.', 'B.', 'C.', 'D.']);
    await h.play();
    expect(engine.spoken, ['A.', 'B.', 'C.']);
    expect(h.snapshot.value.playing, isFalse);
    expect(h.snapshot.value.message, 'El motor de voz no está disponible.');
    tmp.deleteSync(recursive: true);
  });

  test('con el temporizador "al terminar el capítulo" pausa justo antes del siguiente', () async {
    final engine = SlowEngine();
    final (h, tmp) = await handlerWith(engine, ['A.', 'B.', 'C.', 'D.'], onePerPage: true);
    h.chapters = const [Chapter(title: 'Uno', pageIndex: 0), Chapter(title: 'Dos', pageIndex: 2)];
    unawaited(h.play());
    await until(() => engine.pending.length == 1);
    h.setSleepAtChapterEnd();
    engine.finishCurrent(); // A.
    await until(() => engine.spoken.length == 2 && engine.pending.length == 1);
    engine.finishCurrent(); // B.: el capítulo termina
    await until(() => !h.snapshot.value.playing);
    expect(engine.spoken, ['A.', 'B.']);
    expect(h.snapshot.value.playing, isFalse);
    expect(h.chunkIndex, 2); // al seguir, empieza el capítulo siguiente
    expect(h.sleepAtChapterEnd.value, isFalse);
    tmp.deleteSync(recursive: true);
  });

  test('con "saltar citas" no pronuncia las referencias', () async {
    final engine = SlowEngine();
    final (h, tmp) = await handlerWith(engine, ['El poder corrompe [12].']);
    Comfort.skipCitations.value = true;
    addTearDown(() => Comfort.skipCitations.value = false);
    unawaited(h.play());
    await until(() => engine.spoken.isNotEmpty);
    expect(engine.spoken, ['El poder corrompe.']);
    engine.finishCurrent();
    await until(() => !h.snapshot.value.playing);
    tmp.deleteSync(recursive: true);
  });
}
