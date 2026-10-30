import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/math/graph.dart';

/// Gráfico de la solución: ejes con cuadrícula, la parábola o las rectas y
/// los puntos que importan (raíces, vértice, cruce), sobre el fondo negro.
class MathGraphView extends StatelessWidget {
  const MathGraphView({super.key, required this.graph});
  final MathGraph graph;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // En tablet no ocupa todo el ancho: un tamaño de hoja de cuaderno.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: AspectRatio(
          aspectRatio: 1.4,
          child: Semantics(
            image: true,
            label: 'Gráfico de la ecuación',
            child: CustomPaint(
              painter: _GraphPainter(
                graph,
                axis: scheme.onSurface.withValues(alpha: 0.6),
                grid: scheme.onSurface.withValues(alpha: 0.08),
                colors: [scheme.primary, const Color(0xFFFF9F0A)],
                point: scheme.onSurface,
                label: Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(
    this.graph, {
    required this.axis,
    required this.grid,
    required this.colors,
    required this.point,
    required this.label,
  });
  final MathGraph graph;
  final Color axis, grid, point;
  final List<Color> colors;
  final TextStyle label;

  @override
  void paint(Canvas canvas, Size size) {
    final w = graph.window();
    // Misma escala en x y en y no siempre conviene (parábolas altas): cada
    // eje usa la suya y la cuadrícula marca las unidades.
    Offset at(double x, double y) => Offset(
      (x - w.minX) / (w.maxX - w.minX) * size.width,
      size.height - (y - w.minY) / (w.maxY - w.minY) * size.height,
    );
    canvas.clipRect(Offset.zero & size);

    final gridPaint = Paint()..color = grid;
    final stepX = _niceStep(w.maxX - w.minX), stepY = _niceStep(w.maxY - w.minY);
    for (var x = (w.minX / stepX).ceil() * stepX; x <= w.maxX; x += stepX) {
      canvas.drawLine(at(x, w.minY), at(x, w.maxY), gridPaint);
    }
    for (var y = (w.minY / stepY).ceil() * stepY; y <= w.maxY; y += stepY) {
      canvas.drawLine(at(w.minX, y), at(w.maxX, y), gridPaint);
    }
    final axisPaint = Paint()
      ..color = axis
      ..strokeWidth = 1.2;
    canvas.drawLine(at(w.minX, 0), at(w.maxX, 0), axisPaint);
    canvas.drawLine(at(0, w.minY), at(0, w.maxY), axisPaint);
    _text(canvas, 'x', at(w.maxX, 0) + const Offset(-12, 4));
    _text(canvas, 'y', at(0, w.maxY) + const Offset(6, 2));

    for (final (i, c) in graph.curves.indexed) {
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..strokeWidth = 2.6
        ..style = PaintingStyle.stroke;
      final vx = c.verticalX;
      if (vx != null) {
        canvas.drawLine(at(vx, w.minY), at(vx, w.maxY), paint);
        continue;
      }
      final path = Path();
      const n = 240;
      for (var k = 0; k <= n; k++) {
        final x = w.minX + (w.maxX - w.minX) * k / n;
        final p = at(x, c.at(x));
        if (k == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, paint);
    }

    final dot = Paint()..color = point;
    for (final p in graph.points) {
      final o = at(p.x, p.y);
      canvas.drawCircle(o, 5, dot);
      _text(canvas, p.label, o + const Offset(8, -18));
    }
  }

  void _text(Canvas canvas, String s, Offset o) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: label),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, o);
    tp.dispose();
  }

  /// Paso de cuadrícula "redondo" (1, 2, 5, 10…) para unos 8 cuadros.
  static double _niceStep(double span) {
    final raw = span / 8;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    for (final m in [1, 2, 5, 10]) {
      if (raw <= m * mag) return m * mag;
    }
    return 10 * mag;
  }

  @override
  bool shouldRepaint(_GraphPainter old) => old.graph != graph;
}
