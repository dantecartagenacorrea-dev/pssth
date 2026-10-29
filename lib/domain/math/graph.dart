/// Una curva para graficar: la parábola o recta y = a·x² + b·x + c, o una
/// recta vertical x = [verticalX].
class MathCurve {
  const MathCurve({this.a = 0, this.b = 0, this.c = 0, this.verticalX, required this.label});
  final double a, b, c;
  final double? verticalX;
  final String label;

  double at(double x) => a * x * x + b * x + c;
}

/// Un punto marcado en el gráfico (raíz, vértice, cruce de rectas).
typedef MathPoint = ({double x, double y, String label});

/// Lo que se dibuja junto a la solución.
class MathGraph {
  const MathGraph({required this.curves, required this.points});
  final List<MathCurve> curves;
  final List<MathPoint> points;

  /// Ventana a mostrar: alrededor de los puntos marcados, con margen.
  ({double minX, double maxX, double minY, double maxY}) window() {
    final xs = [for (final p in points) p.x, for (final c in curves) ?c.verticalX];
    final ys = [for (final p in points) p.y];
    double lo(List<double> v) => v.isEmpty ? 0 : v.reduce((a, b) => a < b ? a : b);
    double hi(List<double> v) => v.isEmpty ? 0 : v.reduce((a, b) => a > b ? a : b);
    final cx = (lo(xs) + hi(xs)) / 2, spanX = (hi(xs) - lo(xs)).abs();
    final halfX = (spanX * 0.8).clamp(4.0, 1e6);
    final minX = cx - halfX, maxX = cx + halfX;
    final cy = (lo(ys) + hi(ys)) / 2, spanY = (hi(ys) - lo(ys)).abs();
    final halfY = (spanY * 0.8).clamp(4.0, 1e6);
    return (minX: minX, maxX: maxX, minY: cy - halfY, maxY: cy + halfY);
  }
}
