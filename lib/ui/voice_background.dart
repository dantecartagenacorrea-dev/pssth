import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../playback/tts_audio_handler.dart';

/// Fondo del reproductor que reacciona a la voz: una esfera de partículas que
/// gira despacio y se deforma con el volumen (voz natural) o con cada palabra
/// (voz del sistema). En pausa queda casi quieta; con "Reducir movimiento", fija.
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
    return RepaintBoundary(
      child: CustomPaint(painter: _SpherePainter(_paint), size: Size.infinite),
    );
  }
}

class _BlobState extends ChangeNotifier {
  double energy = 0;
  double phase = 0;
  void notify() => notifyListeners();
}

/// Esfera de puntos repartidos en espiral (Fibonacci) sobre su superficie; su
/// radio ondula con la energía de la voz y unas bandas brillan como vetas.
class _SpherePainter extends CustomPainter {
  _SpherePainter(this.state) : super(repaint: state);

  final _BlobState state;

  static const _count = 2600;
  static const _levels = 6;
  static final List<(double, double, double)> _unit = [
    for (var i = 0; i < _count; i++)
      () {
        final y = 1 - 2 * (i + 0.5) / _count;
        final r = math.sqrt(1 - y * y);
        final th = i * math.pi * (3 - math.sqrt(5));
        return (math.cos(th) * r, y, math.sin(th) * r);
      }(),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final e = state.energy;
    final t = state.phase * 2.2;
    final cx = size.width / 2, cy = size.height * 0.42;
    final radius = size.shortestSide * 0.36;
    final ry = t * 0.35, rx = 0.35 * math.sin(t * 0.13);
    final cyr = math.cos(ry), syr = math.sin(ry), cxr = math.cos(rx), sxr = math.sin(rx);
    final amp = 0.05 + 0.32 * e;
    final groups = List.generate(_levels, (_) => <double>[]);
    for (final (ux, uy, uz) in _unit) {
      final lat = math.asin(uy), lon = math.atan2(uz, ux);
      // Deformación: ondas que recorren la esfera y crecen con la voz.
      final wave = math.sin(3 * lat + t * 1.3) * math.cos(2 * lon - t) * 0.6 + math.sin(5 * lon + t * 2.1) * 0.4;
      final k = 1 + amp * wave;
      var x = ux * k, y = uy * k, z = uz * k;
      // Giro: primero sobre el eje vertical, luego un leve cabeceo.
      final x1 = x * cyr + z * syr;
      final z1 = -x * syr + z * cyr;
      final y1 = y * cxr - z1 * sxr;
      final z2 = y * sxr + z1 * cxr;
      x = x1;
      y = y1;
      z = z2;
      final persp = 1 / (1.9 - z * 0.6);
      // Vetas: bandas brillantes que se arremolinan con el tiempo.
      final band = math.pow((math.sin(4 * lat + 2 * lon + t * 0.8) + 1) / 2, 6).toDouble();
      final depth = (z + 1) / 2; // 0 atrás, 1 adelante
      final light = (0.15 + 0.55 * depth + 0.6 * band) * (0.7 + 0.5 * e);
      final l = (light.clamp(0.0, 1.0) * (_levels - 1)).round();
      groups[l]
        ..add(cx + x * radius * persp * 1.9)
        ..add(cy + y * radius * persp * 1.9);
    }
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.5;
    for (var l = 0; l < _levels; l++) {
      if (groups[l].isEmpty) continue;
      paint.color = Colors.white.withValues(alpha: 0.06 + 0.5 * l / (_levels - 1));
      canvas.drawRawPoints(PointMode.points, Float32List.fromList(groups[l]), paint);
    }
  }

  @override
  bool shouldRepaint(_SpherePainter old) => false;
}
