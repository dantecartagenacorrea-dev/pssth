import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'core/perf_log.dart';
import 'services/llm_cleaner.dart';
import 'theme/app_theme.dart';
import 'package:path_provider/path_provider.dart';

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
import 'ui/dot_field.dart';
import 'ui/swarm.dart';
import 'ui/swarm_transition.dart';
import 'ui/intro_screen.dart';
import 'ui/library_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Medición de fluidez en un equipo real: solo con --dart-define=MEDIR=true.
  if (kMedir) _logFrameTimings();
  final boot = Stopwatch()..start();
  void mark(String what) {
    perfLog('arranque: $what ${boot.elapsedMilliseconds} ms');
  }
  // Lo que no depende entre sí arranca a la vez. El lector de PDF ya no se
  // prepara aquí: lo hace la primera vez que se abre un PDF.
  final libraryStore = LibraryStore();
  final dirs = await Future.wait([
    getApplicationDocumentsDirectory(),
    getTemporaryDirectory(),
    LlmCleaner.instance.load().then((_) { mark('ajustes IA'); }),
    libraryStore.init().then((_) { mark('biblioteca'); }),
    DotField.load().then((_) { mark('fondo GPU'); }),
  ]);
  mark('en paralelo');
  final docs = dirs[0]!, cacheDir = dirs[1]!;
  final settingsStore = SettingsStore();
  final pronunciationStore = PronunciationStore(File('${libraryStore.root.path}/pronunciation.json'));
  final bookmarkStore = BookmarkStore(File('${libraryStore.root.path}/bookmarks.json'));

  // Voz natural (opcional): modelo en <documentos>/models/kokoro; sin él solo hay voces del sistema.
  final modelStore = ModelStore(Directory('${docs.path}/models'));
  final engine = FallbackTtsEngine(
    primary: KokoroEngine(
      modelDir: modelStore.dirFor(kokoroEsModel).path,
      cache: AudioCache(Directory('${cacheDir.path}/tts_audio')),
    ),
    fallback: AppleTtsEngine(),
    startWithPrimary: false,
  );

  mark('motores');
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

  mark('servicio de audio');
  // La voz se prepara mientras ya se ve la entrada (no frena la primera imagen).
  unawaited(handler.setup().then((_) => mark('voz lista')));
  Swarm.instance.handler = handler;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    mark('primer cuadro');
    // Las letras del enjambre se dibujan después de la primera imagen: la
    // entrada no las necesita y prepararlas tomaba más de un segundo.
    unawaited(Swarm.instance.init().then((_) => mark('enjambre')));
  });
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

  static final _ether = AppTheme.ether().copyWith(
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: SwarmTransitionsBuilder(),
        TargetPlatform.iOS: SwarmTransitionsBuilder(),
        TargetPlatform.macOS: SwarmTransitionsBuilder(),
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
      // El enjambre de letras vuela por encima de todas las pantallas.
      builder: (context, child) => Stack(
        children: [
          ?child,
          const Positioned.fill(child: SwarmView()),
        ],
      ),
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

/// Cada 120 cuadros escribe en el registro cuánto tardó cada cuadro en
/// prepararse (hilo de la interfaz) y en dibujarse (GPU).
void _logFrameTimings() {
  final build = <int>[], raster = <int>[];
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      build.add(t.buildDuration.inMicroseconds);
      raster.add(t.rasterDuration.inMicroseconds);
    }
    if (build.length < 120) return;
    String stats(List<int> v) {
      v.sort();
      return 'p50 ${(v[v.length ~/ 2] / 1000).toStringAsFixed(1)} ms, p90 ${(v[(v.length * 0.9).floor()] / 1000).toStringAsFixed(1)} ms';
    }
    // ignore: avoid_print
    print('[medir] interfaz ${stats(build)} | dibujo ${stats(raster)}');
    build.clear();
    raster.clear();
  });
}
