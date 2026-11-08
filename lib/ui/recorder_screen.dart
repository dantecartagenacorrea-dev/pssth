import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../domain/level_booster.dart';
import '../domain/live_audio.dart';
import '../platform/nemo_transcriber.dart';
import 'premium.dart';

const _sampleRate = 16000;

/// Grabación terminada: archivo de audio, duración y, si se fue transcribiendo
/// mientras se grababa, el texto que termina de armarse.
class RecordingResult {
  RecordingResult(this.path, this.duration, {this.transcript});
  final String path;
  final Duration duration;
  final Future<String>? transcript;
}

/// Pantalla austera: un botón grande para grabar/detener. Todo queda en el dispositivo.
class RecorderScreen extends StatefulWidget {
  const RecorderScreen({super.key, this.liveModelDir});

  /// Carpeta del dictado en español si se puede transcribir mientras se graba.
  final String? liveModelDir;

  @override
  State<RecorderScreen> createState() => _RecorderScreenState();
}

class _RecorderScreenState extends State<RecorderScreen> {
  final _recorder = AudioRecorder();
  bool _recording = false;
  String? _error;
  String? _path;
  final _watch = Stopwatch();
  Timer? _ticker;
  StreamSubscription<Amplitude>? _levels;

  /// Volumen del micrófono, 0 (silencio) a 1 (fuerte), para que se vea que graba.
  double _level = 0;

  /// Un rato en silencio total: avisar por si el micrófono no capta.
  int _quietTicks = 0;

  NemoLiveSession? _live;
  String _liveText = '';
  final _pcm = Pcm16Decoder();
  final _booster = LevelBooster();
  IOSink? _wav;
  int _wavBytes = 0;
  StreamSubscription<Uint8List>? _audio;
  Completer<void>? _audioDone;

  @override
  void dispose() {
    _ticker?.cancel();
    _levels?.cancel();
    _audio?.cancel();
    _live?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  void _listenLevels() {
    _levels = _recorder.onAmplitudeChanged(const Duration(milliseconds: 80)).listen((a) {
      // dBFS: −60 o menos es silencio, 0 es el máximo.
      final v = ((a.current + 60) / 60).clamp(0.0, 1.0);
      if (!mounted) return;
      setState(() {
        _level = _level * 0.5 + v * 0.5;
        _quietTicks = v < 0.08 ? _quietTicks + 1 : 0;
      });
    });
  }

  String get _clock {
    final s = _watch.elapsed.inSeconds;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(s ~/ 3600)}:${two((s % 3600) ~/ 60)}:${two(s % 60)}';
  }

  /// Un toque doble en empezar o detener no debe correr dos veces.
  bool _busy = false;

  Future<void> _once(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    try {
      await action();
    } finally {
      _busy = false;
    }
  }

  Future<void> _start() => _once(_startRecording);

  Future<void> _stop() => _once(_stopRecording);

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        setState(() => _error = 'Sin permiso de micrófono. Actívalo en Ajustes.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/grabacion_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _startStream(path);
      _path = path;
      _watch
        ..reset()
        ..start();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
      _listenLevels();
      setState(() {
        _recording = true;
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo iniciar la grabación.');
    }
  }

  /// Graba el audio a mano para subirle el volumen y, si se puede, ir dándoselo
  /// al reconocedor mientras se graba.
  Future<void> _startStream(String path) async {
    final modelDir = widget.liveModelDir;
    final live = modelDir == null
        ? null
        : await NemoLiveSession.start(
            modelDir: modelDir,
            sampleRate: _sampleRate,
            onText: (text) {
              if (mounted) setState(() => _liveText = text);
            },
          );
    _live = live;
    final wav = File(path).openWrite()..add(Uint8List(44));
    _wav = wav;
    _wavBytes = 0;
    final done = Completer<void>();
    _audioDone = done;
    final stream = await _recorder.startStream(
      const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: _sampleRate, numChannels: 1),
    );
    _audio = stream.listen(
      (bytes) {
        final samples = _booster.process(_pcm.convert(bytes));
        final boosted = pcm16Bytes(samples);
        wav.add(boosted);
        _wavBytes += boosted.length;
        live?.add(samples);
      },
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
      onError: (_) {
        if (!done.isCompleted) done.complete();
      },
    );
  }

  /// Cierra el archivo con su cabecera, ya sabiendo cuánto audio tiene.
  Future<void> _closeWav(String path) async {
    final wav = _wav;
    if (wav == null) return;
    await _audioDone?.future.timeout(const Duration(seconds: 2), onTimeout: () {});
    await _audio?.cancel();
    await wav.close();
    final file = await File(path).open(mode: FileMode.append);
    try {
      await file.setPosition(0);
      await file.writeFrom(pcm16WavHeader(dataBytes: _wavBytes, sampleRate: _sampleRate));
    } finally {
      await file.close();
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    _ticker?.cancel();
    await _levels?.cancel();
    _watch.stop();
    try {
      await _recorder.stop();
    } catch (_) {}
    final path = _path;
    if (path != null) await _closeWav(path);
    if (!mounted) return;
    if (path == null || !File(path).existsSync() || File(path).lengthSync() <= (_wav == null ? 0 : 44)) {
      setState(() {
        _recording = false;
        _error = 'La grabación quedó vacía.';
      });
      return;
    }
    final live = _live;
    _live = null;
    Navigator.pop(context, RecordingResult(path, _watch.elapsed, transcript: _wavBytes > 0 ? live?.finish() : null));
  }

  Future<void> _cancel() async {
    _ticker?.cancel();
    try {
      await _recorder.cancel();
    } catch (_) {}
    final path = _path;
    if (path != null && _wav != null) {
      try {
        await _closeWav(path);
        await File(path).delete();
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_recording,
      child: PremiumPage(
        title: 'Grabar',
        subtitle: 'Clase o conversación',
        leading: IconButton(
          tooltip: 'Cancelar',
          icon: const Icon(CupertinoIcons.xmark),
          onPressed: _recording ? _cancel : () => Navigator.pop(context),
        ),
        body: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                Semantics(liveRegion: true, child: Text(_clock, style: Theme.of(context).textTheme.displayMedium)),
                const SizedBox(height: 32),
                SizedBox(
                  width: 240,
                  height: 240,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Anillo que crece con la voz: se ve que el micrófono capta.
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 80),
                        width: 160 + (_recording ? 80 * _level : 0),
                        height: 160 + (_recording ? 80 * _level : 0),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cs.error.withValues(alpha: _recording ? 0.12 + 0.3 * _level : 0),
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        height: 160,
                        child: Semantics(
                          button: true,
                          label: _recording ? 'Detener grabación' : 'Empezar a grabar',
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              shape: const CircleBorder(),
                              backgroundColor: _recording ? cs.error : cs.primary,
                            ),
                            onPressed: _recording ? _stop : _start,
                            child: Icon(_recording ? CupertinoIcons.stop_fill : CupertinoIcons.mic_fill, size: 72),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (_recording)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Punto rojo que parpadea cada segundo, como en una grabadora.
                      AnimatedOpacity(
                        opacity: _watch.elapsed.inSeconds.isEven ? 1 : 0.2,
                        duration: const Duration(milliseconds: 300),
                        child: Icon(CupertinoIcons.circle_fill, size: 14, color: cs.error),
                      ),
                      const SizedBox(width: 8),
                      const Text('GRABANDO · toca para detener'),
                    ],
                  )
                else
                  const Text('Toca para grabar'),
                if (_recording && _quietTicks > 60) ...[
                  const SizedBox(height: 8),
                  Text('No se escucha nada: acércate al micrófono.', style: TextStyle(color: cs.error)),
                ],
                if (_error != null) ...[const SizedBox(height: 12), Text(_error!, style: TextStyle(color: cs.error))],
                if (_recording && widget.liveModelDir != null) ...[
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      reverse: true,
                      child: SizedBox(
                        width: double.infinity,
                        child: Text(
                          _liveText.isEmpty ? 'El texto irá apareciendo por partes mientras grabas…' : _liveText,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ] else
                  const Spacer(),
                Text(
                  'Avisa a las personas que grabas y obtén su consentimiento cuando la ley lo exija. '
                  'El audio y el texto se guardan solo en este dispositivo.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
