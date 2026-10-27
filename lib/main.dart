import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import 'services/llm_cleaner.dart';
import 'theme/app_theme.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import 'data/bookmark_store.dart';
import 'data/library_store.dart';
import 'data/model_store.dart';
import 'data/pronunciation_store.dart';
import 'data/settings_store.dart';
import 'data/audio_cache.dart';
import 'playback/engines/apple_tts_engine.dart';
import 'playback/engines/fallback_tts_engine.dart';
import 'playback/engines/kokoro_engine.dart';
import 'playback/tts_audio_handler.dart';
import 'ui/disintegrate_transition.dart';
import 'ui/intro_screen.dart';
import 'ui/library_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LlmCleaner.instance.load();
  await pdfrxFlutterInitialize();

  final libraryStore = LibraryStore();
  await libraryStore.init();
  final settingsStore = SettingsStore();
  final pronunciationStore = PronunciationStore(File('${libraryStore.root.path}/pronunciation.json'));
  final bookmarkStore = BookmarkStore(File('${libraryStore.root.path}/bookmarks.json'));

  // Voz natural (opcional): modelo en <documentos>/models/kokoro; sin él solo hay voces del sistema.
  final docs = await getApplicationDocumentsDirectory();
  final cacheDir = await getTemporaryDirectory();
  final modelStore = ModelStore(Directory('${docs.path}/models'));
  final engine = FallbackTtsEngine(
    primary: KokoroEngine(
      modelDir: modelStore.dirFor(kokoroEsModel).path,
      cache: AudioCache(Directory('${cacheDir.path}/tts_audio')),
    ),
    fallback: AppleTtsEngine(),
    startWithPrimary: false,
  );

  final handler = await AudioService.init(
    builder: () => TtsAudioHandler(
      libraryStore: libraryStore,
      settingsStore: settingsStore,
      engine: engine,
    ),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.lectorpdf.lectorPdf.tts',
      androidNotificationChannelName: 'Lectura PDF',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
    ),
  );

  await handler.setup();
  await DisintegrateTransitionsBuilder.load();

  runApp(
    LectorPdfApp(
      handler: handler,
      libraryStore: libraryStore,
      settingsStore: settingsStore,
      bookmarkStore: bookmarkStore,
      pronunciationStore: pronunciationStore,
      modelStore: modelStore,
      onModelsChanged: () async {
        await engine.retryPrimary();
        await handler.reloadVoices();
      },
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
    required this.modelStore,
    required this.onModelsChanged,
  });

  final TtsAudioHandler handler;
  final LibraryStore libraryStore;
  final SettingsStore settingsStore;
  final BookmarkStore bookmarkStore;
  final PronunciationStore pronunciationStore;
  final ModelStore modelStore;
  final Future<void> Function() onModelsChanged;

  static final _ether = AppTheme.dark().copyWith(
    scaffoldBackgroundColor: Colors.transparent,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: DisintegrateTransitionsBuilder(),
        TargetPlatform.iOS: DisintegrateTransitionsBuilder(),
        TargetPlatform.macOS: DisintegrateTransitionsBuilder(),
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PSSTH!',
      // Toda la app en negro, sobre el fondo de puntos que trae cada pantalla;
      // al entrar y salir, las pantallas se desintegran y se reconstruyen.
      theme: _ether,
      darkTheme: _ether,
      themeMode: ThemeMode.dark,
      home: IntroScreen(
        next: (_) => LibraryScreen(
          handler: handler,
          libraryStore: libraryStore,
          settingsStore: settingsStore,
          bookmarkStore: bookmarkStore,
          pronunciationStore: pronunciationStore,
          modelStore: modelStore,
          onModelsChanged: onModelsChanged,
        ),
      ),
    );
  }
}
