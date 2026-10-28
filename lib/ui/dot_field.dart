import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Fondo de todas las pantallas: negro con una malla de puntos que ondula como
/// tela y unos hilos de luz hechos de partículas que fluyen despacio. Con
/// "Reducir movimiento" queda quieto.
class DotField extends StatefulWidget {
  const DotField({super.key});

  /// Programa de GPU que dibuja el fondo; se carga una vez al iniciar. Sin él
  /// (no cargó), se dibuja en el procesador como antes.
  static ui.FragmentProgram? program;

  static Future<void> load() async {
    try {
      program = await ui.FragmentProgram.fromAsset('shaders/dot_field.frag');
    } catch (_) {
      program = null;
    }
  }

  @override
  State<DotField> createState() => _DotFieldState();
}

class _DotFieldState extends State<DotField> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((d) => _time.value = d.inMicroseconds / 1e6);
  final _time = ValueNotifier<double>(0);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.disableAnimationsOf(context);
    if (still && _ticker.isActive) _ticker.stop();
    if (!still && !_ticker.isActive) _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _shader?.dispose();
    super.dispose();
  }

  late final ui.FragmentShader? _shader = DotField.program?.fragmentShader();

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    return RepaintBoundary(
      child: CustomPaint(
        painter: shader != null ? _GpuDotFieldPainter(_time, shader) : _DotFieldPainter(_time),
        size: Size.infinite,
      ),
    );
  }
}

/// El mismo fondo, calculado por la tarjeta gráfica: un solo rectángulo.
class _GpuDotFieldPainter extends CustomPainter {
  _GpuDotFieldPainter(this.time, this.shader) : super(repaint: time);

  final ValueNotifier<double> time;
  final ui.FragmentShader shader;

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time.value);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_GpuDotFieldPainter old) => false;
}

class _DotFieldPainter extends CustomPainter {
  _DotFieldPainter(this.time) : super(repaint: time);

  final ValueNotifier<double> time;

  static const _gap = 14.0; // separación de la malla
  static const _levels = 6; // brillos distintos (una pasada de dibujo por brillo)
  static const _threads = 3;
  static const _threadDots = 160;

  Float32List _buffer = Float32List(0);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    final t = time.value;
    final cols = (size.width / _gap).ceil() + 1;
    final rows = (size.height / _gap).ceil() + 1;
    final n = cols * rows;
    if (_buffer.length < n * 2) _buffer = Float32List(n * 2);
    final level = Uint8List(n);
    final counts = List.filled(_levels, 0);
    // Malla: cada punto sube y baja con dos ondas cruzadas; brilla más en la cresta.
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final x = c * _gap, y = r * _gap;
        final h = math.sin(x * 0.018 + t * 0.6) * math.cos(y * 0.011 - t * 0.4) +
            0.5 * math.sin((x + y) * 0.01 + t * 0.9);
        final i = r * cols + c;
        _buffer[i * 2] = x + h * 4;
        _buffer[i * 2 + 1] = y + h * 16;
        final l = (((h + 1.5) / 3) * (_levels - 1)).round().clamp(0, _levels - 1);
        level[i] = l;
        counts[l]++;
      }
    }
    final ordered = Float32List(n * 2);
    final start = List.filled(_levels + 1, 0);
    for (var l = 0; l < _levels; l++) {
      start[l + 1] = start[l] + counts[l];
    }
    final fill = List.of(start);
    for (var i = 0; i < n; i++) {
      final at = fill[level[i]]++ * 2;
      ordered[at] = _buffer[i * 2];
      ordered[at + 1] = _buffer[i * 2 + 1];
    }
    final dot = Paint()
      ..strokeCap = StrokeCap.square
      ..strokeWidth = 1.6;
    for (var l = 0; l < _levels; l++) {
      if (counts[l] == 0) continue;
      dot.color = Colors.white.withValues(alpha: 0.05 + 0.22 * l / (_levels - 1));
      canvas.drawRawPoints(PointMode.points, Float32List.sublistView(ordered, start[l] * 2, start[l + 1] * 2), dot);
    }
    // Hilos de luz: trayectorias que serpentean y se deshilachan en partículas.
    final threads = Float32List(_threads * _threadDots * 2);
    var k = 0;
    for (var th = 0; th < _threads; th++) {
      for (var j = 0; j < _threadDots; j++) {
        final s = j / _threadDots;
        final wobble = math.sin(j * 12.9898 + th * 78.233) * 6;
        threads[k++] = size.width * (0.5 + 0.42 * math.sin(s * 2.4 + t * 0.25 + th * 2.1)) + wobble;
        threads[k++] = size.height * s + 40 * math.sin(s * 9 + t * 0.7 + th) + wobble;
      }
    }
    canvas.drawRawPoints(
      PointMode.points,
      threads,
      Paint()
        ..strokeCap = StrokeCap.square
        ..strokeWidth = 1.8
        ..color = Colors.white.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
  }

  @override
  bool shouldRepaint(_DotFieldPainter old) => false;
}
