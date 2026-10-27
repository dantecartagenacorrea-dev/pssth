import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../playback/tts_audio_handler.dart';

/// Fondo del reproductor que reacciona a la voz: manchas de luz suaves que se
/// mueven despacio y crecen con el volumen (voz natural) o con cada palabra
/// (voz del sistema). En pausa quedan tenues; con "Reducir movimiento" quietas.
class VoiceBackground extends StatefulWidget {
  const VoiceBackground({super.key, required this.handler});

  final TtsAudioHandler handler;

  @override
  State<VoiceBackground> createState() => _VoiceBackgroundState();
}

class _VoiceBackgroundState extends State<VoiceBackground>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _paint = _BlobState();
  Duration _last = Duration.zero;

  /// Impulso de la última palabra (voces sin audio propio); decae solo.
  double _pulse = 0;

  TtsAudioHandler get _h => widget.handler;

  @override
  void initState() {
    super.initState();
    _h.wordRange.addListener(_onWord);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still && _ticker.isActive) _ticker.stop();
    if (!still && !_ticker.isActive) _ticker.start();
  }

  void _onWord() {
    if (_h.wordRange.value != null) _pulse = 0.85;
  }

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.1);
    _last = now;
    final playing = _h.snapshot.value.playing;
    _pulse = math.max(0, _pulse - dt * 2.5);
    final target = playing ? math.max(_h.voiceLevel.value, _pulse) : 0.0;
    // Sube rápido con la voz y baja despacio: se ve como respiración, no parpadeo.
    final rate = target > _paint.energy ? 12.0 : 2.5;
    _paint.energy += (target - _paint.energy) * (1 - math.exp(-rate * dt));
    // Avanza más rápido mientras habla; en pausa casi se detiene.
    _paint.phase += dt * (playing ? 0.35 + _paint.energy * 0.6 : 0.06);
    _paint.notify();
  }

  @override
  void dispose() {
    _h.wordRange.removeListener(_onWord);
    _ticker.dispose();
    _paint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _BlobPainter(_paint, [
          scheme.primary,
          scheme.tertiary,
          scheme.secondary,
        ]),
        size: Size.infinite,
      ),
    );
  }
}

class _BlobState extends ChangeNotifier {
  double energy = 0;
  double phase = 0;
  void notify() => notifyListeners();
}

class _BlobPainter extends CustomPainter {
  _BlobPainter(this.state, this.colors) : super(repaint: state);

  final _BlobState state;
  final List<Color> colors;

  // Recorrido de cada mancha (frecuencias distintas para que no se sincronicen).
  static const _paths = [(0.7, 0.5, 0.0), (0.45, 0.8, 2.1), (0.9, 0.35, 4.2)];

  @override
  void paint(Canvas canvas, Size size) {
    final e = state.energy;
    final t = state.phase;
    final base = size.shortestSide;
    for (var i = 0; i < _paths.length; i++) {
      final (fx, fy, off) = _paths[i];
      final center = Offset(
        size.width * (0.5 + 0.32 * math.sin(t * fx + off)),
        size.height * (0.45 + 0.3 * math.cos(t * fy + off * 1.3)),
      );
      final radius =
          base * (0.45 + 0.25 * e) * (1 + 0.08 * math.sin(t * 2 + off));
      final color = colors[i % colors.length];
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.10 + 0.22 * e),
            color.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_BlobPainter old) => old.colors != colors;
}
