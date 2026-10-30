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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pausar y reanudar rápido no deja dos lecturas a la par', () async {
    final engine = SlowEngine();
    final (h, tmp) = await handlerWith(engine, ['Uno.', 'Dos.', 'Tres.']);
    unawaited(h.play());
    await settle();
    await h.pause();
    unawaited(h.play()); // reanuda antes de que la frase anterior termine
    await settle();
    // Termina la frase vieja (la del bucle pausado): no debe avanzar por su cuenta.
    engine.finishCurrent();
    await settle();
    expect(engine.spoken, ['Uno.', 'Uno.']);
    engine.finishCurrent(); // termina la frase del bucle vigente
    await settle();
    expect(engine.spoken, ['Uno.', 'Uno.', 'Dos.']);
    expect(h.chunkIndex, 1);
    await h.stop();
    tmp.deleteSync(recursive: true);
  });

  test('una frase que falla se salta y la lectura sigue', () async {
    final engine = SlowEngine()..failing.add('Dos.');
    final (h, tmp) = await handlerWith(engine, ['Uno.', 'Dos.', 'Tres.']);
    unawaited(h.play());
    await settle();
    engine.finishCurrent(); // Uno.
    await settle();
    expect(engine.spoken, ['Uno.', 'Dos.', 'Tres.']);
    expect(h.snapshot.value.message, isNull);
    engine.finishCurrent(); // Tres.
    await settle();
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
    await settle();
    h.setSleepAtChapterEnd();
    engine.finishCurrent(); // A.
    await settle();
    engine.finishCurrent(); // B.: el capítulo termina
    await settle();
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
    await settle();
    expect(engine.spoken, ['El poder corrompe.']);
    engine.finishCurrent();
    await settle();
    tmp.deleteSync(recursive: true);
  });
}
