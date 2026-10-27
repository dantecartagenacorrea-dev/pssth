import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'dot_field.dart';

/// Transición entre pantallas: la nueva se reconstruye desde el polvo, celda a
/// celda y en desorden, sobre la que se va; al volver, la que se cierra se
/// desintegra. En el borde que avanza saltan chispas de polvo.
class DisintegrateTransitionsBuilder extends PageTransitionsBuilder {
  const DisintegrateTransitionsBuilder();

  /// Programa de la máscara; se carga una vez al iniciar la app.
  static ui.FragmentProgram? program;

  static Future<void> load() async {
    try {
      program = await ui.FragmentProgram.fromAsset('shaders/dissolve.frag');
    } catch (_) {
      program = null; // sin la máscara se usa un fundido simple
    }
  }

  @override
  Duration get transitionDuration => const Duration(milliseconds: 800);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Cada pantalla trae su propio fondo de puntos: así lo que se desintegra es
    // la pantalla entera, no solo su contenido.
    final page = Stack(fit: StackFit.expand, children: [const DotField(), child]);
    if (MediaQuery.disableAnimationsOf(context)) return FadeTransition(opacity: animation, child: page);
    return _Disintegrate(animation: animation, child: page);
  }
}

class _Disintegrate extends StatelessWidget {
  const _Disintegrate({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  static const _cell = 10.0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) {
        final p = Curves.easeInOut.transform(animation.value);
        if (p >= 1) return child!;
        final program = DisintegrateTransitionsBuilder.program;
        if (program == null) return Opacity(opacity: p, child: child);
        return Stack(
          fit: StackFit.expand,
          children: [
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => program.fragmentShader()
                ..setFloat(0, rect.width)
                ..setFloat(1, rect.height)
                ..setFloat(2, p)
                ..setFloat(3, _cell),
              child: child,
            ),
            IgnorePointer(child: CustomPaint(painter: _SparksPainter(p))),
          ],
        );
      },
    );
  }
}

/// Chispas en las celdas que están apareciendo o deshaciéndose: suben y se apagan.
class _SparksPainter extends CustomPainter {
  _SparksPainter(this.progress);

  final double progress;

  static const _cell = 20.0;
  static double _hash(double x, double y) {
    final v = math.sin(x * 127.1 + y * 311.7) * 43758.5453;
    return v - v.floorToDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final pts = <double>[];
    final cols = (size.width / _cell).ceil(), rows = (size.height / _cell).ceil();
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final v = _hash(c.toDouble(), r.toDouble()) * 0.75 + (r * _cell / size.height) * 0.25;
        final d = progress - v;
        if (d < 0 || d > 0.08) continue;
        final rise = d / 0.08;
        pts
          ..add(c * _cell + _cell / 2 + (_hash(r.toDouble(), c.toDouble()) - 0.5) * 14)
          ..add(r * _cell + _cell / 2 - rise * 26);
      }
    }
    if (pts.isEmpty) return;
    canvas.drawRawPoints(
      ui.PointMode.points,
      Float32List.fromList(pts),
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.2
        ..color = Colors.white.withValues(alpha: 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
  }

  @override
  bool shouldRepaint(_SparksPainter old) => old.progress != progress;
}
