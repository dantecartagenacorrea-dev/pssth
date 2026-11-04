import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/data/library_store.dart';
import 'package:lector_pdf/data/settings_store.dart';
import 'package:lector_pdf/domain/library_entry.dart';
import 'package:lector_pdf/domain/text_chunk.dart';
import 'package:lector_pdf/playback/tts_audio_handler.dart';
import 'package:lector_pdf/playback/tts_engine.dart';
import 'package:lector_pdf/ui/reading_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SilentEngine extends TtsEngine {
  @override
  String get id => 'silent';
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
  Future<void> speak(String text) async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

const _text = 'La casa del pueblo';
const _spokenDifferently = 'Texto que la voz dice de otra forma';

void main() {
  late TtsAudioHandler handler;
  late Directory tmp;

  Future<void> setUpHandler(WidgetTester tester) async {
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
      tmp = Directory.systemTemp.createTempSync('reading');
      final store = LibraryStore();
      await store.initAt(tmp);
      handler = TtsAudioHandler(libraryStore: store, settingsStore: SettingsStore(), engine: _SilentEngine());
      await handler.setup();
      final entry = LibraryEntry(id: 'd', name: 'd.txt', storedPath: '', pageCount: 1, totalChunks: 1);
      await store.upsert(entry);
      await handler.loadDocument(
        entry: entry,
        chunks: [TextChunk(documentId: 'd', pageIndex: 0, chunkIndex: 0, text: _text)],
      );
    });
    addTearDown(() => tmp.deleteSync(recursive: true));
  }

  Future<void> show(WidgetTester tester, {String text = _text, int relation = 0}) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ReadingText(handler: handler, text: text, relation: relation),
      ),
    ),
  );

  /// Lo que está marcado con el color de la palabra (tema claro): null si nada.
  String? marked(WidgetTester tester) {
    String? found;
    tester.widget<RichText>(find.byType(RichText)).text.visitChildren((span) {
      if (span is TextSpan && span.style?.color == const Color(0xFFBA7517)) found = span.text;
      return found == null;
    });
    return found;
  }

  testWidgets('marca la palabra que suena y sigue a la voz', (tester) async {
    await setUpHandler(tester);
    await show(tester);
    expect(marked(tester), isNull);

    handler.wordRange.value = (3, 7);
    await tester.pump();
    expect(marked(tester), 'casa');

    handler.wordRange.value = (12, 18);
    await tester.pump();
    expect(marked(tester), 'pueblo');
    expect(find.text(_text, findRichText: true), findsOneWidget);

    handler.wordRange.value = null;
    await tester.pump();
    expect(marked(tester), isNull);
  });

  testWidgets('no marca nada en un fragmento que no es el que suena', (tester) async {
    await setUpHandler(tester);
    await show(tester, relation: 1);
    handler.wordRange.value = (3, 7);
    await tester.pump();
    expect(marked(tester), isNull);
  });

  testWidgets('no marca nada si el texto no coincide con lo que dice la voz', (tester) async {
    await setUpHandler(tester);
    await show(tester, text: _spokenDifferently);
    handler.wordRange.value = (3, 7);
    await tester.pump();
    expect(marked(tester), isNull);
  });
}
