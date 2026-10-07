import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Grabación terminada: archivo de audio y duración.
class RecordingResult {
  RecordingResult(this.path, this.duration);
  final String path;
  final Duration duration;
}

/// Pantalla austera: un botón grande para grabar/detener. Todo queda en el dispositivo.
class RecorderScreen extends StatefulWidget {
  const RecorderScreen({super.key});

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

  @override
  void dispose() {
    _ticker?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  String get _clock {
    final s = _watch.elapsed.inSeconds;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(s ~/ 3600)}:${two((s % 3600) ~/ 60)}:${two(s % 60)}';
  }

  Future<void> _start() async {
    try {
      if (!await _recorder.hasPermission()) {
        setState(() => _error = 'Sin permiso de micrófono. Actívalo en Ajustes.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/grabacion_${DateTime.now().millisecondsSinceEpoch}.wav';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
        path: path,
      );
      _path = path;
      _watch
        ..reset()
        ..start();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
      setState(() {
        _recording = true;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = 'No se pudo iniciar la grabación.');
    }
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    _watch.stop();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    path ??= _path;
    if (!mounted) return;
    if (path == null || !File(path).existsSync() || File(path).lengthSync() == 0) {
      setState(() {
        _recording = false;
        _error = 'La grabación quedó vacía.';
      });
      return;
    }
    Navigator.pop(context, RecordingResult(path, _watch.elapsed));
  }

  Future<void> _cancel() async {
    _ticker?.cancel();
    try {
      await _recorder.cancel();
    } catch (_) {}
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_recording,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Grabar'),
          leading: IconButton(
            tooltip: 'Cancelar',
            icon: const Icon(Icons.close),
            onPressed: _recording ? _cancel : () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _clock,
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                ),
                const SizedBox(height: 32),
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
                      child: Icon(_recording ? Icons.stop : Icons.mic, size: 72),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(_recording ? 'Grabando… toca para detener' : 'Toca para grabar'),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: cs.error)),
                ],
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
