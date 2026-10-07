import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/data/library_store.dart';
import 'package:lector_pdf/data/settings_store.dart';
import 'package:lector_pdf/domain/library_entry.dart';
import 'package:lector_pdf/domain/text_chunk.dart';
import 'package:lector_pdf/playback/tts_audio_handler.dart';
import 'package:lector_pdf/playback/tts_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecEngine extends TtsEngine {
  final spoken = <String>[];
  final calls = <String>[];
  final prefetched = <List<String>>[];
  @override
  String get id => 'rec';
  @override
  Future<void> init() async {}
  @override
  Future<List<VoiceOption>> voices() async => const [
        VoiceOption(name: 'Mónica', locale: 'es-ES', quality: 'enhanced'),
        VoiceOption(name: 'Samantha', locale: 'en-US', quality: 'enhanced'),
      ];
  @override
  Future<void> setVoice(VoiceOption voice) async => calls.add('voice:${voice.name}');
  @override
  Future<void> setLanguage(String locale) async => calls.add('lang:$locale');
  @override
  Future<void> setRate(double rate) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    calls.add('speak');
  }

  @override
  void prefetch(List<String> upcoming) => prefetched.add(upcoming);
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

const es1 = 'La casa estaba en el centro del pueblo y todos los vecinos conocían a sus dueños desde hacía años.';
const en = 'The house was in the middle of the town and all of the neighbors knew the owners from the years that they had lived there.';
const es2 = 'Por la tarde los niños jugaban en la plaza mientras los mayores hablaban de la cosecha y del tiempo.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cambia de voz solo en el bloque en inglés y prepara los siguientes fragmentos', () async {
    SharedPreferences.setMockInitialValues({});
    final tmp = Directory.systemTemp.createTempSync('lib');
    final store = LibraryStore();
    await store.initAt(tmp);
    final engine = RecEngine();
    final h = TtsAudioHandler(libraryStore: store, settingsStore: SettingsStore(), engine: engine);
    await h.setup();
    final entry = LibraryEntry(id: 'd', name: 'd.txt', storedPath: '', pageCount: 1, totalChunks: 3);
    await store.upsert(entry);
    final chunks = [
      TextChunk(documentId: 'd', pageIndex: 0, chunkIndex: 0, text: es1),
      TextChunk(documentId: 'd', pageIndex: 0, chunkIndex: 1, text: en),
      TextChunk(documentId: 'd', pageIndex: 0, chunkIndex: 2, text: es2),
    ];
    await h.loadDocument(entry: entry, chunks: chunks);
    await h.applyDocumentLanguage('es');
    engine.calls.clear();
    await h.play();
    expect(engine.spoken, [es1, en, es2]);
    // Voz es → inglés antes del 2.º fragmento → vuelve a español antes del 3.º.
    expect(engine.calls, ['speak', 'voice:Samantha', 'speak', 'voice:Mónica', 'speak']);
    expect(engine.prefetched.first, [en, es2]);
    expect(engine.prefetched.last, isEmpty);
    tmp.deleteSync(recursive: true);
  });
}
