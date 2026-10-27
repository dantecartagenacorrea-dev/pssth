import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Entrada de la app: fondo negro, puntos en caos que se juntan como atraídos
/// por un imán y forman el ícono de PSSTH!, que luego se desintegra para dar
/// paso a la biblioteca. Un toque la salta; con "Reducir movimiento" es breve.
class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key, required this.next});

  /// Pantalla que sigue (la biblioteca).
  final WidgetBuilder next;

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> with SingleTickerProviderStateMixin {
  static const _chaos = 0.9, _form = 2.2, _hold = 2.8, _end = 3.6; // segundos
  late final Ticker _ticker = createTicker(_tick);
  final _time = ValueNotifier<double>(0);
  _Dots? _dots;
  bool _left = false;
  double _skipFrom = double.infinity;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dots = await _Dots.fromAsset('assets/branding/logo.png');
    if (!mounted) return;
    setState(() => _dots = dots);
    if (MediaQuery.disableAnimationsOf(context)) {
      _time.value = _hold;
      Future.delayed(const Duration(milliseconds: 600), _leave);
      return;
    }
    _ticker.start();
  }

  void _tick(Duration d) {
    final t = d.inMicroseconds / 1e6;
    // Al tocar, salta directo a la desintegración.
    _time.value = t >= _skipFrom ? _hold + (t - _skipFrom) : t;
    if (_time.value >= _end - 0.35) _leave();
  }

  void _skip() {
    if (_skipFrom.isFinite) return;
    _skipFrom = _ticker.isActive ? _time.value : 0;
  }

  void _leave() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: widget.next));
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dots = _dots;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: ColoredBox(
        color: Colors.black,
        child: Semantics(
          label: 'PSSTH!',
          child: dots == null ? const SizedBox.expand() : CustomPaint(painter: _IntroPainter(dots, _time), size: Size.infinite),
        ),
      ),
    );
  }
}

/// Puntos tomados del ícono: posición dentro de la imagen y color.
class _Dots {
  _Dots(this.x, this.y, this.color, this.aspect, this.seedA, this.seedB);

  final Float32List x, y; // 0–1 dentro del ícono
  final Int32List color;
  final double aspect; // alto / ancho
  final Float32List seedA, seedB;

  static const _maxDots = 5000;

  static Future<_Dots> fromAsset(String asset) async {
    final data = await rootBundle.load(asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List(), targetWidth: 220);
    final image = (await codec.getNextFrame()).image;
    final w = image.width, h = image.height;
    final bytes = (await image.toByteData())!;
    image.dispose();
    final xs = <double>[], ys = <double>[], cs = <int>[];
    for (var py = 0; py < h; py++) {
      for (var px = 0; px < w; px++) {
        final o = (py * w + px) * 4;
        final a = bytes.getUint8(o + 3);
        if (a < 140) continue;
        final r = bytes.getUint8(o), g = bytes.getUint8(o + 1), b = bytes.getUint8(o + 2);
        if (r > 245 && g > 245 && b > 245) continue; // fondo blanco, si lo hubiera
        xs.add(px / w);
        ys.add(py / w);
        cs.add(0xFF000000 | (r << 16) | (g << 8) | b);
      }
    }
    // Si hay demasiados, se toma una muestra pareja.
    final rnd = math.Random(7);
    final keep = <int>[for (var i = 0; i < xs.length; i++) i]..shuffle(rnd);
    final n = math.min(_maxDots, keep.length);
    return _Dots(
      Float32List.fromList([for (var i = 0; i < n; i++) xs[keep[i]]]),
      Float32List.fromList([for (var i = 0; i < n; i++) ys[keep[i]]]),
      Int32List.fromList([for (var i = 0; i < n; i++) cs[keep[i]]]),
      h / w,
      Float32List.fromList([for (var i = 0; i < n; i++) rnd.nextDouble()]),
      Float32List.fromList([for (var i = 0; i < n; i++) rnd.nextDouble()]),
    );
  }
}

class _IntroPainter extends CustomPainter {
  _IntroPainter(this.dots, this.time) : super(repaint: time);

  final _Dots dots;
  final ValueNotifier<double> time;

  // Colores reducidos a una paleta corta: una pasada de dibujo por color.
  static int _bucket(int c) => (((c >> 16) & 0xFF) >> 6) << 4 | (((c >> 8) & 0xFF) >> 6) << 2 | ((c & 0xFF) >> 6);
  static Color _bucketColor(int b) => Color.fromARGB(255, ((b >> 4) & 3) * 85, ((b >> 2) & 3) * 85, (b & 3) * 85);

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final n = dots.x.length;
    final iconW = size.width * 0.78;
    final iconH = iconW * dots.aspect;
    final ox = (size.width - iconW) / 2, oy = (size.height - iconH) / 2;
    // Caos inicial: un rectángulo de ruido, como estática, centrado.
    final noiseW = size.width * 0.62, noiseH = size.height * 0.5;
    final nx = (size.width - noiseW) / 2, ny = (size.height - noiseH) / 2;
    final frame = (t * 24).floor(); // la estática cambia 24 veces por segundo
    final groups = <int, List<double>>{};
    var fade = 1.0;
    if (t > _IntroScreenState._hold) {
      fade = 1 - ((t - _IntroScreenState._hold) / (_IntroScreenState._end - _IntroScreenState._hold)).clamp(0.0, 1.0);
    }
    for (var i = 0; i < n; i++) {
      final a = dots.seedA[i], b = dots.seedB[i];
      final hx = ox + dots.x[i] * iconW, hy = oy + dots.y[i] * iconW;
      final jx = _rand(i, frame), jy = _rand(i + 7919, frame);
      final cx = nx + jx * noiseW, cy = ny + jy * noiseH;
      double x, y;
      if (t < _IntroScreenState._chaos) {
        x = cx;
        y = cy;
      } else if (t < _IntroScreenState._form) {
        // Imán: cada punto se suelta a su turno y acelera al acercarse.
        final local = ((t - _IntroScreenState._chaos) / (_IntroScreenState._form - _IntroScreenState._chaos) * 1.6 - b * 0.6)
            .clamp(0.0, 1.0);
        final e = local * local * local;
        final swirl = math.sin(local * math.pi) * 40 * (a - 0.5);
        x = cx + (hx - cx) * e + swirl;
        y = cy + (hy - cy) * e - swirl * 0.5;
      } else if (t < _IntroScreenState._hold) {
        x = hx;
        y = hy;
      } else {
        // Desintegración: el viento lo arrastra hacia la derecha y arriba.
        final k = ((t - _IntroScreenState._hold) / (_IntroScreenState._end - _IntroScreenState._hold) * 1.4 - (1 - dots.x[i]) * 0.4)
            .clamp(0.0, 1.0);
        final e = k * k;
        x = hx + e * (180 + 260 * a) + math.sin(t * 6 + b * 9) * 6 * k;
        y = hy - e * (120 + 200 * b);
      }
      final bucket = t < _IntroScreenState._chaos ? -1 : _bucket(dots.color[i]);
      (groups[bucket] ??= <double>[])
        ..add(x)
        ..add(y);
    }
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.2;
    groups.forEach((bucket, pts) {
      final base = bucket < 0 ? Colors.white : _bucketColor(bucket);
      paint.color = base.withValues(alpha: (bucket < 0 ? 0.75 : 0.95) * fade);
      canvas.drawRawPoints(ui.PointMode.points, Float32List.fromList(pts), paint);
    });
  }

  /// Azar repetible por punto y por cuadro (la estática).
  static double _rand(int i, int frame) {
    final v = math.sin(i * 12.9898 + frame * 78.233) * 43758.5453;
    return v - v.floorToDouble();
  }

  @override
  bool shouldRepaint(_IntroPainter old) => old.dots != dots;
}
