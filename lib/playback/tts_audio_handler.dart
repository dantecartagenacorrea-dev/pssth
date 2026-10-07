import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../data/library_store.dart';
import '../data/settings_store.dart';
import '../domain/chapter_detector.dart';
import '../domain/library_entry.dart';
import '../domain/reading_position.dart';
import '../domain/text_chunk.dart';
import '../domain/voice_ranking.dart';
import 'engines/apple_tts_engine.dart';
import 'tts_engine.dart';

export 'tts_engine.dart' show VoiceOption;

class PlayerSnapshot {
  const PlayerSnapshot({
    required this.title,
    required this.pageIndex,
    required this.pageCount,
    required this.chunkIndex,
    required this.linearIndex,
    required this.totalChunks,
    required this.currentText,
    required this.playing,
    required this.speed,
    required this.voices,
    required this.selectedVoiceId,
    required this.hasText,
    this.message,
  });

  final String title;
  final int pageIndex;
  final int pageCount;
  final int chunkIndex;
  final int linearIndex;
  final int totalChunks;
  final String currentText;
  final bool playing;
  final double speed;
  final List<VoiceOption> voices;
  final String? selectedVoiceId;
  final bool hasText;
  final String? message;

  double get progress {
    if (totalChunks <= 0) {
      return 0;
    }
    return ((linearIndex + 1) / totalChunks).clamp(0, 1);
  }
}

const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// Convierte el multiplicador de velocidad (1.0 = normal) al rango del motor
/// (0.0-1.0, donde 0.5 es la velocidad normal).
double ttsRateFor(double multiplier) => (0.5 * multiplier).clamp(0.1, 1.0).toDouble();

class TtsAudioHandler extends BaseAudioHandler {
  TtsAudioHandler({
    required this.libraryStore,
    required this.settingsStore,
    TtsEngine? engine,
  }) : _tts = engine ?? AppleTtsEngine();

  final LibraryStore libraryStore;
  final SettingsStore settingsStore;
  final TtsEngine _tts;
  final ValueNotifier<PlayerSnapshot> snapshot = ValueNotifier(
    const PlayerSnapshot(
      title: '',
      pageIndex: 0,
      pageCount: 0,
      chunkIndex: 0,
      linearIndex: 0,
      totalChunks: 0,
      currentText: '',
      playing: false,
      speed: 1,
      voices: [],
      selectedVoiceId: null,
      hasText: false,
    ),
  );

  /// Rango (inicio, fin) de la palabra que se está leyendo en el bloque actual.
  final ValueNotifier<(int, int)?> wordRange = ValueNotifier(null);
  int _lastIndex = -1;

  List<TextChunk> _chunks = [];
  int _index = 0;
  LibraryEntry? _entry;
  bool _ready = false;
  bool _speaking = false;
  bool _keepIndexAfterStop = false;
  List<VoiceOption> _voices = [];
  String? _voiceName;
  /// Voz realmente en uso (puede diferir de la guardada si el documento está en otro idioma).
  VoiceOption? _activeVoice;
  String? _voiceLocale;
  double _speed = 1;

  Future<void> setup() async {
    if (_ready) {
      return;
    }
    _tts.onProgress = (String text, int start, int end) {
      final c = currentChunk;
      if (c == null || c.speech != text) return;
      wordRange.value = (start, end);
    };
    _tts.onError = (message) {
      _speaking = false;
      _refresh(playing: false, message: 'El motor de voz no está disponible.');
      _broadcastState(playing: false);
    };
    await _tts.init();
    try {
      await _tts.setVolume(1.0); // máximo del motor; más alto solo con el volumen del sistema
    } catch (_) {}
    try {
      await _tts.setLanguage('es-ES');
    } catch (_) {}
    await _loadVoices();
    final prefs = await settingsStore.load();
    _speed = _nearestSpeed(prefs.speed);
    _voiceName = prefs.voiceName;
    _voiceLocale = prefs.voiceLocale;
    await _applyVoice();
    await _applySpeed();
    _ready = true;
    _refresh();
  }

  Future<void> loadDocument({
    required LibraryEntry entry,
    required List<TextChunk> chunks,
    String? noTextMessage,
    String? notice,
  }) async {
    await stop();
    _entry = entry;
    _chunks = chunks;
    final keys = chunks
        .map((c) => (pageIndex: c.pageIndex, chunkIndex: c.chunkIndex))
        .toList();
    _index = entry.finished
        ? 0 // un documento terminado se vuelve a escuchar desde el principio
        : ReadingPosition(
            pageIndex: entry.pageIndex,
            chunkIndex: entry.chunkIndex,
          ).resolveChunkListIndex(keys);
    mediaItem.add(
      MediaItem(
        id: entry.id,
        title: entry.name,
        album: 'LECTOR PDF',
        duration: Duration(seconds: chunks.isEmpty ? 1 : chunks.length),
      ),
    );
    _refresh(
      hasText: chunks.isNotEmpty,
      message: chunks.isEmpty ? noTextMessage : notice,
      playing: false,
    );
    _broadcastState(playing: false);
  }

  /// Sustituye los bloques (p. ej. al terminar el OCR de nuevas páginas)
  /// conservando la posición actual.
  Future<void> replaceChunks(List<TextChunk> chunks) async {
    final current = _chunks.isEmpty ? null : _chunks[_index];
    _chunks = chunks;
    final keys = chunks
        .map((c) => (pageIndex: c.pageIndex, chunkIndex: c.chunkIndex))
        .toList();
    final pos = current != null
        ? ReadingPosition(
            pageIndex: current.pageIndex,
            chunkIndex: current.chunkIndex,
          )
        : ReadingPosition(
            pageIndex: _entry?.pageIndex ?? 0,
            chunkIndex: _entry?.chunkIndex ?? 0,
          );
    _index = pos.resolveChunkListIndex(keys);
    _refresh(hasText: chunks.isNotEmpty);
  }

  /// Ajusta el idioma de la voz al del documento si la voz elegida por el
  /// usuario no es de ese idioma. No modifica las preferencias guardadas.
  Future<void> applyDocumentLanguage(String? lang) async {
    if (lang == null) return;
    final saved = _voiceLocale;
    if (_voiceName != null && saved != null && saved.toLowerCase().startsWith(lang)) {
      // La voz elegida sirve para este idioma: restaurarla por si el documento
      // anterior usó una voz temporal de otro idioma.
      await _applyVoice();
      _refresh();
      return;
    }
    // Mejor voz disponible para el idioma (premium > mejorada > local > genérica).
    final match = rankVoices<VoiceOption>(
      _voices.where((v) => v.locale.toLowerCase().startsWith(lang)),
      name: (v) => v.name,
      locale: (v) => v.locale,
      quality: (v) => v.quality,
    );
    try {
      if (match.isNotEmpty) {
        await _tts.setVoice(match.first);
        _activeVoice = match.first;
      } else {
        await _tts.setLanguage(lang);
        _activeVoice = null;
      }
    } catch (_) {}
    _refresh();
  }

  Future<void> _loadVoices() async {
    _voices = await _tts.voices();
  }

  Future<void> _applyVoice() async {
    if (_voiceName == null || _voices.isEmpty) {
      return;
    }
    final exists = _voices.any(
      (v) => v.name == _voiceName && v.locale == _voiceLocale,
    );
    if (!exists) {
      _voiceName = null;
      _voiceLocale = null;
      await settingsStore.saveVoice();
      _refresh(
        message:
            'La voz guardada ya no está disponible. Se usará la voz del sistema.',
      );
      return;
    }
    try {
      await _tts.setVoice(VoiceOption(name: _voiceName!, locale: _voiceLocale ?? ''));
      _activeVoice = VoiceOption(name: _voiceName!, locale: _voiceLocale ?? '');
    } catch (_) {
      _voiceName = null;
      _voiceLocale = null;
      _activeVoice = null;
    }
  }

  Future<void> _applySpeed() async {
    try {
      await _tts.setRate(ttsRateFor(_speed));
    } catch (_) {}
  }

  double _nearestSpeed(double value) {
    return speeds.reduce(
      (a, b) => (a - value).abs() < (b - value).abs() ? a : b,
    );
  }

  @override
  Future<void> play() async {
    if (kDebugMode) debugPrint('[lector] play() idx=$_index speaking=$_speaking chunks=${_chunks.length}');
    if (_chunks.isEmpty) {
      _refresh(playing: false);
      return;
    }
    if (_speaking) {
      return; // ya hay un bucle de lectura en marcha
    }
    _speaking = true;
    _broadcastState(playing: true);
    _refresh(playing: true, message: null);
    while (_speaking && _index < _chunks.length) {
      try {
        final speech = _chunks[_index].speech;
        if (kDebugMode) debugPrint('[lector] speak idx=$_index len=${speech.length} "${speech.length > 70 ? speech.substring(0, 70) : speech}"');
        if (speech.trim().isNotEmpty) {
          await _tts.stop();
          await _tts.speak(speech);
        }
      } catch (_) {
        _speaking = false;
        _refresh(
          playing: false,
          message: 'No se pudo iniciar la lectura en voz alta.',
        );
        _broadcastState(playing: false);
        return;
      }
      if (!_speaking) {
        break;
      }
      if (_keepIndexAfterStop) {
        _keepIndexAfterStop = false;
        continue;
      }
      if (_index >= _chunks.length - 1) {
        _speaking = false;
        _broadcastState(playing: false);
        _refresh(playing: false);
        await _persistPosition(finished: true);
        return;
      }
      _index += 1;
      await _persistPosition();
      _refresh(playing: true);
      _broadcastState(playing: true);
    }
  }

  @override
  Future<void> pause() async {
    if (kDebugMode) debugPrint('[lector] pause() idx=$_index speaking=$_speaking');
    _speaking = false;
    try {
      await _tts.pause();
    } catch (_) {
      await _tts.stop();
    }
    _broadcastState(playing: false);
    _refresh(playing: false);
    await _persistPosition();
  }

  @override
  Future<void> click([MediaButton button = MediaButton.media]) async {
    if (kDebugMode) debugPrint('[lector] click($button) desde el sistema');
    return super.click(button);
  }

  @override
  Future<void> stop() async {
    _speaking = false;
    await _tts.stop();
    _broadcastState(playing: false);
    _refresh(playing: false);
    await _persistPosition();
  }

  @override
  Future<void> skipToNext() async {
    if (kDebugMode) debugPrint('[lector] skipToNext idx=$_index');
    if (_chunks.isEmpty) {
      return;
    }
    final wasPlaying = _speaking;
    if (_index >= _chunks.length - 1) {
      return;
    }
    _index += 1;
    await _persistPosition();
    _refresh(playing: wasPlaying);
    if (wasPlaying) {
      _keepIndexAfterStop = true;
      await _tts.stop();
    }
  }

  @override
  Future<void> skipToPrevious() async {
    if (kDebugMode) debugPrint('[lector] skipToPrevious idx=$_index');
    if (_chunks.isEmpty) {
      return;
    }
    final wasPlaying = _speaking;
    if (_index > 0) {
      _index -= 1;
    }
    await _persistPosition();
    _refresh(playing: wasPlaying);
    if (wasPlaying) {
      _keepIndexAfterStop = true;
      await _tts.stop();
    }
  }

  @override
  Future<void> setSpeed(double speed) async {
    if (kDebugMode) debugPrint('[lector] setSpeed($speed)');
    _speed = _nearestSpeed(speed);
    await _applySpeed();
    await settingsStore.saveSpeed(_speed);
    _refresh();
  }

  Future<void> setVoice(VoiceOption? voice) async {
    _voiceName = voice?.name;
    _voiceLocale = voice?.locale;
    _activeVoice = null;
    await settingsStore.saveVoice(name: _voiceName, locale: _voiceLocale);
    await _applyVoice();
    _refresh();
  }

  /// Lee un texto suelto (p. ej. el resumen) sin cambiar la posición del documento.
  Future<void> speakAside(String text) async {
    await pause();
    try {
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> stopAside() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  /// Texto original por página (para exportar y buscar), sin normalizar.
  List<String> pages = const [];

  final ValueNotifier<DateTime?> sleepEndsAt = ValueNotifier(null);
  Timer? _sleepTimer;

  /// Temporizador de sueño: al terminar pausa y conserva el progreso.
  void setSleepTimer(Duration? duration) {
    _sleepTimer?.cancel();
    if (duration == null) {
      sleepEndsAt.value = null;
      return;
    }
    sleepEndsAt.value = DateTime.now().add(duration);
    _sleepTimer = Timer(duration, () async {
      sleepEndsAt.value = null;
      await pause();
    });
  }

  List<Chapter> chapters = [];
  List<TextChunk> get chunks => _chunks;
  TextChunk? get currentChunk => _chunks.isEmpty ? null : _chunks[_index];

  Future<void> jumpToIndex(int index) async {
    if (kDebugMode) debugPrint('[lector] jumpToIndex($index)');
    if (_chunks.isEmpty) return;
    await _moveTo(index.clamp(0, _chunks.length - 1).toInt());
  }

  /// Salta al inicio de una página (o a la siguiente con texto).
  Future<void> jumpToPage(int pageIndex) async {
    if (kDebugMode) debugPrint('[lector] jumpToPage($pageIndex)');
    final i = _chunks.indexWhere((c) => c.pageIndex >= pageIndex);
    if (i >= 0) await _moveTo(i);
  }

  /// Salta a una posición guardada (página + bloque).
  Future<void> jumpToPosition(int pageIndex, int chunkIndex) async {
    if (kDebugMode) debugPrint('[lector] jumpToPosition($pageIndex,$chunkIndex)');
    if (_chunks.isEmpty) return;
    final keys = _chunks
        .map((c) => (pageIndex: c.pageIndex, chunkIndex: c.chunkIndex))
        .toList();
    await _moveTo(
      ReadingPosition(pageIndex: pageIndex, chunkIndex: chunkIndex)
          .resolveChunkListIndex(keys),
    );
  }

  Future<void> nextPage() => _jumpTo(
        (i) => _chunks[i].pageIndex > _chunks[_index].pageIndex,
        forward: true,
      );

  Future<void> previousPage() async {
    if (_chunks.isEmpty) return;
    final page = _chunks[_index].pageIndex;
    // Si ya se avanzó dentro de la página, vuelve a su inicio; si no, a la anterior.
    final startOfPage = _chunks.indexWhere((c) => c.pageIndex == page);
    if (_index > startOfPage) {
      await _moveTo(startOfPage);
      return;
    }
    await _jumpTo(
      (i) => _chunks[i].pageIndex < page,
      forward: false,
    );
  }

  Future<void> _jumpTo(bool Function(int) test, {required bool forward}) async {
    if (_chunks.isEmpty) return;
    int? target;
    if (forward) {
      for (var i = _index + 1; i < _chunks.length; i++) {
        if (test(i)) {
          target = i;
          break;
        }
      }
    } else {
      for (var i = _index - 1; i >= 0; i--) {
        if (test(i)) {
          // inicio de esa página anterior
          final pg = _chunks[i].pageIndex;
          target = _chunks.indexWhere((c) => c.pageIndex == pg);
          break;
        }
      }
    }
    if (target != null) await _moveTo(target);
  }

  Future<void> _moveTo(int target) async {
    if (kDebugMode) debugPrint('[lector] _moveTo($target) speaking=$_speaking');
    final wasPlaying = _speaking;
    _index = target;
    await _persistPosition();
    _refresh(playing: wasPlaying);
    if (wasPlaying) {
      _keepIndexAfterStop = true;
      await _tts.stop();
    }
  }

  Future<void> _persistPosition({bool? finished}) async {
    final entry = _entry;
    if (entry == null || _chunks.isEmpty) {
      return;
    }
    final chunk = _chunks[_index];
    await libraryStore.updatePosition(
      id: entry.id,
      pageIndex: chunk.pageIndex,
      chunkIndex: chunk.chunkIndex,
      finished: finished ?? (_index < _chunks.length - 1 ? false : null),
    );
  }

  void _refresh({bool? playing, bool? hasText, String? message}) {
    if (_index != _lastIndex) {
      _lastIndex = _index;
      wordRange.value = null;
    }
    if (_chunks.isEmpty) {
      snapshot.value = PlayerSnapshot(
        title: _entry?.name ?? '',
        pageIndex: _entry?.pageIndex ?? 0,
        pageCount: _entry?.pageCount ?? 0,
        chunkIndex: _entry?.chunkIndex ?? 0,
        linearIndex: 0,
        totalChunks: 0,
        currentText: '',
        playing: false,
        speed: _speed,
        voices: _voices,
        selectedVoiceId: _activeVoice?.id,
        hasText: hasText ?? false,
        message: message,
      );
      return;
    }
    final chunk = _chunks[_index];
    snapshot.value = PlayerSnapshot(
      title: _entry?.name ?? '',
      pageIndex: chunk.pageIndex,
      pageCount: _entry?.pageCount ?? 0,
      chunkIndex: chunk.chunkIndex,
      linearIndex: _index,
      totalChunks: _chunks.length,
      currentText: chunk.text,
      playing: playing ?? _speaking,
      speed: _speed,
      voices: _voices,
      selectedVoiceId: _activeVoice?.id,
      hasText: true,
      message: message,
    );
  }

  void _broadcastState({required bool playing}) {
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        androidCompactActionIndices: const [0, 1, 2],
        processingState: AudioProcessingState.ready,
        playing: playing,
        updatePosition: Duration(seconds: _index),
        speed: _speed,
      ),
    );
  }
}
