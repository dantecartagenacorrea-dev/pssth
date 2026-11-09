import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show LicenseRegistry, LicenseEntryWithLineBreaks;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'core/motion.dart';
import 'core/perf_log.dart';
import 'services/llm_cleaner.dart';
import 'theme/app_theme.dart';
import 'package:path_provider/path_provider.dart';

import 'core/crash_log.dart';
import 'data/bookmark_store.dart';
import 'data/highlight_store.dart';
import 'data/listening_store.dart';
import 'data/library_store.dart';
import 'data/model_queue.dart';
import 'data/model_store.dart';
import 'data/temp_cleanup.dart';
import 'data/pronunciation_store.dart';
import 'data/settings_store.dart';
import 'data/sync_service.dart';
import 'services/sync_controller.dart';
import 'data/audio_cache.dart';
import 'playback/engines/apple_tts_engine.dart';
import 'playback/engines/fallback_tts_engine.dart';
import 'playback/engines/kokoro_engine.dart';
import 'playback/tts_audio_handler.dart';
import 'ui/activity_badge.dart';
import 'ui/library_screen.dart';

const _pix2textLicense = '''MIT License

Copyright (c) 2022 BreezeDeus

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.''';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Los errores quedan anotados en el aparato (no se envían solos).
  CrashLog.install();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Atkinson Hyperlegible'], await rootBundle.loadString('assets/fonts/OFL.txt'));
    yield LicenseEntryWithLineBreaks(['Inter'], await rootBundle.loadString('assets/fonts/Inter-OFL.txt'));
    yield LicenseEntryWithLineBreaks(['Lista de palabras en español'], await rootBundle.loadString('assets/words/LICENSE.txt'));
    yield const LicenseEntryWithLineBreaks([
      'Supertonic (voz Luna)',
    ], 'Supertonic, Supertone Inc. Modelo bajo licencia OpenRAIL-M (https://huggingface.co/Supertone/supertonic-2/blob/main/LICENSE): '
        'la voz es sintética y no se puede usar para hacerse pasar por personas reales ni para los usos que esa licencia prohíbe.');
    yield const LicenseEntryWithLineBreaks([
      'Dictado en español (NVIDIA Fast Conformer)',
    ], 'NVIDIA NeMo Fast Conformer, español. Creative Commons Attribution 4.0: https://creativecommons.org/licenses/by/4.0/');
    yield const LicenseEntryWithLineBreaks(['Pix2Text MFR (lector de fórmulas)'], _pix2textLicense);
    yield const LicenseEntryWithLineBreaks([
      'UVDoc (aplanador de hojas)',
    ], 'UVDoc, PaddlePaddle. Apache License 2.0: https://www.apache.org/licenses/LICENSE-2.0');
  });
  // Medición de fluidez en un equipo real: solo con --dart-define=MEDIR=true.
  if (kMedir) _logFrameTimings();
  final boot = Stopwatch()..start();
  void mark(String what) {
    perfLog('arranque: $what ${boot.elapsedMilliseconds} ms');
  }

  // Lo que no depende entre sí arranca a la vez. El lector de PDF ya no se
  // prepara aquí: lo hace la primera vez que se abre un PDF.
  final libraryStore = LibraryStore();
  final comfort = Comfort.load();
  final dirs = await Future.wait([
    getApplicationDocumentsDirectory(),
    getTemporaryDirectory(),
    LlmCleaner.instance.load().then((_) {
      mark('ajustes IA');
    }),
    libraryStore.init().then((_) {
      mark('biblioteca');
    }),
  ]);
  await comfort;
  mark('en paralelo');
  final docs = dirs[0]!, cacheDir = dirs[1]!;
  final settingsStore = SettingsStore();
  final pronunciationStore = PronunciationStore(File('${libraryStore.root.path}/pronunciation.json'));
  final bookmarkStore = BookmarkStore(File('${libraryStore.root.path}/bookmarks.json'));
  HighlightStore.instance = HighlightStore(File('${libraryStore.root.path}/highlights.json'));
  ListeningStore.instance = ListeningStore(File('${libraryStore.root.path}/listening.json'));
  // Sincronizar con el Google Drive de la persona (si entró con su cuenta).
  SyncController.instance = SyncController(
    library: libraryStore,
    service: SyncService(
      file: File('${libraryStore.root.path}/sync.json'),
      library: libraryStore,
      bookmarks: bookmarkStore,
      highlights: HighlightStore.instance!,
      pronunciation: pronunciationStore,
      listening: ListeningStore.instance!,
    ),
  );

  // Voces naturales (opcionales, se bajan aparte); sin ellas solo hay voces del sistema.
  final modelStore = ModelStore(Directory('${docs.path}/models'));
  final engine = FallbackTtsEngine(
    primary: KokoroEngine(
      cache: AudioCache(Directory('${cacheDir.path}/tts_audio')),
      piper: [
        for (final (m, name, voice) in [(piperClaudeModel, 'es_MX-claude-high.int8', 'Claude')])
          (
            voice: VoiceOption(name: '$voice (natural)', locale: 'es-MX', quality: 'natural'),
            onnx: '${modelStore.dirFor(m).path}/$name.onnx',
            tokens: '${modelStore.dirFor(m).path}/tokens.txt',
            sid: 0,
            supertonic: false,
          ),
        (
          voice: const VoiceOption(name: 'Luna (natural)', locale: 'es-ES', quality: 'natural'),
          onnx: '${modelStore.dirFor(supertonicModel).path}/vocoder.int8.onnx',
          tokens: '${modelStore.dirFor(supertonicModel).path}/tts.json',
          sid: supertonicSpeaker,
          supertonic: true,
        ),
      ],
    ),
    fallback: AppleTtsEngine(),
    startWithPrimary: false,
  );

  mark('motores');
  final handler = await AudioService.init(
    builder: () => TtsAudioHandler(libraryStore: libraryStore, settingsStore: settingsStore, engine: engine),
    config: AudioServiceConfig(
      androidNotificationChannelId: 'com.lectorpdf.lectorPdf.tts',
      androidNotificationChannelName: 'PSSTH! lectura',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
    ),
  );

  mark('servicio de audio');
  // Modelos opcionales: se bajan cuando la persona los pide.
  ModelQueue.instance = ModelQueue(modelStore, () async {
    await engine.retryPrimary();
    await handler.reloadVoices();
  });

  // Si la voz natural deja de responder, se sigue con la del sistema y se avisa.
  engine.onFallback = (_) => handler.notice('La voz natural no respondió: sigo con la voz del sistema.');
  // La voz se prepara mientras ya se ve la entrada (no frena la primera imagen).
  unawaited(handler.setup().then((_) => mark('voz lista')));

  WidgetsBinding.instance.addPostFrameCallback((_) {
    mark('primer cuadro');
    // Lo que se pidió y se bajó con la app cerrada (gestor de descargas) se instala.
    unawaited(ModelQueue.instance.start());
    // Temporales viejos y restos de la IA quitada (no frena el arranque).
    unawaited(cleanTemporary(cacheDir).then((b) => mark('temporales: ${b ~/ (1024 * 1024)} MB liberados')));
    // Sincroniza al abrir (si ya había entrado) y cada vez que se sale de la app.
    final sync = SyncController.instance!;
    unawaited(sync.start());
    AppLifecycleListener(onHide: () => unawaited(sync.syncNow()));
  });
  startFrameStats(); // solo en la versión de medición
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

  static const _transitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: _FadeTransitions(),
      TargetPlatform.iOS: _FadeTransitions(),
      TargetPlatform.macOS: _FadeTransitions(),
    },
  );
  static final _themes = {
    for (final paper in Paper.values)
      paper: AppTheme.premium(light: paper == Paper.white).copyWith(pageTransitionsTheme: _transitions),
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: Comfort.paper, builder: (context, _) => _app(Comfort.paper.value));
  }

  Widget _app(Paper paper) {
    final theme = _themes[paper]!;
    return MaterialApp(
      title: 'PSSTH!',
      theme: theme,
      darkTheme: theme,
      themeMode: paper == Paper.white ? ThemeMode.light : ThemeMode.dark,
      builder: (context, child) {
        // Fondo liso y quieto: como si el sistema pidiera reducir
        // el movimiento, cada animación aparece de una vez.
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(disableAnimations: true),
          child: ColoredBox(
            color: theme.colorScheme.surface,
            child: Stack(
              children: [
                ?child,
                // Lo que la app hace en segundo plano, arriba y discreto.
                const Positioned.fill(child: ActivityBadge()),
              ],
            ),
          ),
        );
      },
      home: LibraryScreen(
        handler: handler,
        libraryStore: libraryStore,
        settingsStore: settingsStore,
        bookmarkStore: bookmarkStore,
        pronunciationStore: pronunciationStore,
        modelStore: modelStore,
        onModelsChanged: onModelsChanged,
      ),
    );
  }
}

/// Las pantallas cambian con un fundido; la primera aparece de una vez.
class _FadeTransitions extends PageTransitionsBuilder {
  const _FadeTransitions();

  @override
  Duration get transitionDuration => const Duration(milliseconds: 700);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.settings.name == Navigator.defaultRouteName) return child;
    return FadeTransition(opacity: animation, child: child);
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
