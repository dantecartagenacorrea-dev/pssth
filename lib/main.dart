import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'data/bookmark_store.dart';
import 'data/library_store.dart';
import 'data/pronunciation_store.dart';
import 'data/settings_store.dart';
import 'playback/tts_audio_handler.dart';
import 'ui/library_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();

  final libraryStore = LibraryStore();
  await libraryStore.init();
  final settingsStore = SettingsStore();
  final pronunciationStore = PronunciationStore(File('${libraryStore.root.path}/pronunciation.json'));
  final bookmarkStore = BookmarkStore(File('${libraryStore.root.path}/bookmarks.json'));

  final handler = await AudioService.init(
    builder: () => TtsAudioHandler(
      libraryStore: libraryStore,
      settingsStore: settingsStore,
    ),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.lectorpdf.lectorPdf.tts',
      androidNotificationChannelName: 'Lectura PDF',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
    ),
  );

  await handler.setup();

  runApp(
    LectorPdfApp(
      handler: handler,
      libraryStore: libraryStore,
      settingsStore: settingsStore,
      bookmarkStore: bookmarkStore,
      pronunciationStore: pronunciationStore,
    ),
  );
}

class LectorPdfApp extends StatelessWidget {
  const LectorPdfApp({
    super.key,
    required this.handler,
    required this.libraryStore,
    required this.settingsStore,
    required this.bookmarkStore,
    required this.pronunciationStore,
  });

  final TtsAudioHandler handler;
  final LibraryStore libraryStore;
  final SettingsStore settingsStore;
  final BookmarkStore bookmarkStore;
  final PronunciationStore pronunciationStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LECTOR PDF',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B4332)),
        useMaterial3: true,
      ),
      home: LibraryScreen(
        handler: handler,
        libraryStore: libraryStore,
        settingsStore: settingsStore,
        bookmarkStore: bookmarkStore,
        pronunciationStore: pronunciationStore,
      ),
    );
  }
}
