import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../playback/tts_audio_handler.dart';

/// Un carácter de la pantalla: dónde está (en coordenadas de la pantalla),
/// qué letra es y su alto.
typedef SwarmGlyph = ({Offset at, String ch, double height});

enum _Role { free, text, sphere }

class _Bee {
  _Bee(math.Random r)
      : seed = r.nextDouble(),
        sphereIndex = 0,
        ch = 0;

  final double seed;
  double x = 0, y = 0, vx = 0, vy = 0;
  double tx = 0, ty = 0;
  double alpha = 0, targetAlpha = 0;
  double scale = 0.5, targetScale = 0.5;
  int ch; // índice en el atlas
  int sphereIndex;
  _Role role = _Role.free;
}

/// Enjambre de letras que vive en toda la app, como drones: el logo de la
/// entrada se dispersa en él, en la pantalla principal forma la esfera y arma
/// las letras del menú, y al cambiar de pantalla esas letras vuelan a formar
/// los textos de la siguiente. Las pantallas aparecen cuando el enjambre llega.
class Swarm extends ChangeNotifier {
  Swarm._();
  static final instance = Swarm._();

  static const count = 900;
  static const _chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789ÁÉÍÓÚÑáéíóúñü¡!¿?.,:;()-%«»·';

  final _rnd = math.Random(11);
  late final List<_Bee> _bees = List.generate(count, (_) => _Bee(_rnd));
  ui.Image? _atlas;
  final _cells = <String, int>{};
  static const _cellW = 28.0, _cellH = 36.0, _cols = 16;

  /// Tamaño de letra con que están dibujadas las letras del atlas.
  static const atlasFontSize = 26.0;

  /// Para que la esfera palpite con la voz.
  TtsAudioHandler? handler;

  Offset sphereCenter = Offset.zero;
  double sphereRadius = 100;
  double _time = 0, _energy = 0;
  Offset? _swirl; // centro del remolino mientras carga una pantalla

  /// Dibuja las letras una vez en una imagen, para estamparlas por cientos.
  Future<void> init() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    for (var i = 0; i < _chars.length; i++) {
      final ch = _chars[i];
      final cell = Rect.fromLTWH((i % _cols) * _cellW, (i ~/ _cols) * _cellH, _cellW, _cellH);
      final tp = TextPainter(
        text: TextSpan(text: ch, style: const TextStyle(color: Colors.white, fontSize: atlasFontSize)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, cell.center - Offset(tp.width / 2, tp.height / 2));
      tp.dispose();
      _cells[ch] = i;
    }
    final rows = (_chars.length / _cols).ceil();
    _atlas = await recorder.endRecording().toImage((_cols * _cellW).ceil(), (rows * _cellH).ceil());
    for (final b in _bees) {
      b.ch = _rnd.nextInt(_chars.length);
    }
  }

  // Sin atlas todavía (recién abierta la app) cualquier celda sirve: no se dibuja.
  int _cellOf(String ch) => _cells[ch] ?? _cells['·'] ?? 0;

  Rect _rect(int i) => Rect.fromLTWH((i % _cols) * _cellW, (i ~/ _cols) * _cellH, _cellW, _cellH);

  /// Las letras salen de estos puntos (el logo que se dispersa) y se esparcen.
  void scatterFrom(List<Offset> points) {
    if (points.isEmpty) return;
    for (var i = 0; i < _bees.length; i++) {
      final b = _bees[i];
      final p = points[i % points.length];
      final a = b.seed * math.pi * 2;
      b
        ..x = p.dx
        ..y = p.dy
        ..vx = math.cos(a) * 220
        ..vy = math.sin(a) * 220 - 120
        ..tx = p.dx + math.cos(a) * 120
        ..ty = p.dy + math.sin(a) * 120
        ..alpha = 1
        ..targetAlpha = 0.8
        ..scale = 0.3
        ..targetScale = 0.4
        ..role = _Role.free;
    }
  }

  /// Arma los textos de una pantalla: una letra del enjambre por carácter. El
  /// resto forma la esfera (en la pantalla principal) o se apaga.
  void formText(List<SwarmGlyph> glyphs, {required bool sphere}) {
    _swirl = null;
    if (sphere && sphereCenter == Offset.zero) {
      // Antes de que la capa de fondo se dibuje: el centro de la pantalla.
      final view = ui.PlatformDispatcher.instance.views.first;
      final size = view.physicalSize / view.devicePixelRatio;
      sphereCenter = Offset(size.width / 2, size.height * 0.5);
      sphereRadius = size.shortestSide * 0.36;
    }
    // Las letras apagadas salen de los fragmentos de la pantalla anterior: se
    // reparten entre las que se ven, así todo el enjambre nace de lo que había.
    final visible = [for (final b in _bees) if (b.alpha > 0.3) Offset(b.x, b.y)];
    if (visible.isNotEmpty) {
      for (final b in _bees) {
        if (b.alpha > 0.05) continue;
        final p = visible[_rnd.nextInt(visible.length)];
        b
          ..x = p.dx + (b.seed - 0.5) * 24
          ..y = p.dy + (_rnd.nextDouble() - 0.5) * 24
          ..vx = (b.seed - 0.5) * 300
          ..vy = (_rnd.nextDouble() - 0.5) * 300
          ..alpha = 0.6;
      }
    }
    final n = math.min(glyphs.length, _bees.length);
    // Las letras más cercanas a cada carácter llegan primero: se reparten por
    // orden de altura para que el vuelo no se cruce tanto.
    final order = List.generate(_bees.length, (i) => i)..sort((a, b) => _bees[a].y.compareTo(_bees[b].y));
    final sortedGlyphs = List.of(glyphs.take(n))..sort((a, b) => a.at.dy.compareTo(b.at.dy));
    for (var k = 0; k < order.length; k++) {
      final b = _bees[order[k]];
      if (k < n) {
        final g = sortedGlyphs[k];
        b
          ..role = _Role.text
          ..tx = g.at.dx
          ..ty = g.at.dy
          ..ch = _cellOf(g.ch)
          ..targetScale = g.height / _cellH
          ..targetAlpha = 1;
      } else {
        b
          ..role = sphere ? _Role.sphere : _Role.free
          ..sphereIndex = k
          ..targetAlpha = sphere ? 0.45 : 0
          ..targetScale = 0.3;
        if (!sphere) {
          b
            ..tx = b.x + (b.seed - 0.5) * 200
            ..ty = b.y - 150;
        }
      }
    }
  }

  /// El texto real ya se ve: las letras del enjambre se funden en él.
  void settleText() {
    for (final b in _bees) {
      if (b.role == _Role.text) b.targetAlpha = 0;
    }
  }

  /// La pantalla se va: sus letras vuelven a ser del enjambre, en su lugar, y
  /// el resto se junta en un remolino al centro mientras carga la siguiente
  /// (así nunca queda la pantalla en negro).
  void liftText() {
    final view = ui.PlatformDispatcher.instance.views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    final center = Offset(size.width / 2, size.height / 2);
    _swirl = center;
    for (final b in _bees) {
      if (b.role == _Role.text) {
        b
          ..alpha = 1
          ..targetAlpha = 1;
        continue;
      }
      final a = b.seed * math.pi * 2;
      final r = 60 + b.seed * 90;
      b
        ..role = _Role.free
        ..tx = center.dx + math.cos(a) * r
        ..ty = center.dy + math.sin(a) * r
        ..targetAlpha = 0.5
        ..targetScale = 0.3;
    }
  }

  void step(double dt) {
    _time += dt;
    final h = handler;
    final level = h != null && h.snapshot.value.playing ? h.voiceLevel.value : 0.0;
    _energy += (level - _energy) * (1 - math.exp(-(level > _energy ? 12 : 2.5) * dt));
    final t = _time;
    // Esfera viva: gira más rápido, cabecea y respira aunque no haya voz.
    final ry = t * 0.7, rx = 0.5 * math.sin(t * 0.37);
    final cyr = math.cos(ry), syr = math.sin(ry), cxr = math.cos(rx), sxr = math.sin(rx);
    final amp = 0.12 + 0.06 * math.sin(t * 1.7) + 0.3 * _energy;
    const k = 55.0, c = 11.0; // resorte y freno: llegan rápido sin rebotar de más
    for (final b in _bees) {
      if (b.role == _Role.sphere) {
        // Punto de la esfera (espiral de Fibonacci) que le toca, girando.
        final i = b.sphereIndex;
        final yy = 1 - 2 * (i + 0.5) / count;
        final rr = math.sqrt(1 - yy * yy);
        final th = i * math.pi * (3 - math.sqrt(5));
        final lat = math.asin(yy), lon = th;
        final wave = 1 + amp * (math.sin(3 * lat + t * 2.2) * math.cos(2 * lon - t * 1.6) * 0.6 + math.sin(5 * lon + t * 3.1) * 0.4);
        final x0 = math.cos(th) * rr * wave, z0 = math.sin(th) * rr * wave, y0 = yy * wave;
        final x1 = x0 * cyr + z0 * syr, z1 = -x0 * syr + z0 * cyr;
        final y1 = y0 * cxr - z1 * sxr, z2 = y0 * sxr + z1 * cxr;
        final persp = 1 / (1.9 - z2 * 0.6) * 1.9;
        b
          ..tx = sphereCenter.dx + x1 * sphereRadius * persp
          ..ty = sphereCenter.dy + y1 * sphereRadius * persp
          // Tenue como antes: el menú de adelante tiene que leerse.
          ..targetAlpha = 0.1 + 0.4 * (z2 + 1) / 2
          ..targetScale = 0.18 + 0.24 * (z2 + 1) / 2;
      } else if (b.role == _Role.free) {
        final c = _swirl;
        if (c != null) {
          // Remolino de carga: giran alrededor del centro.
          final dx = b.tx - c.dx, dy = b.ty - c.dy;
          final w = 1.4 * dt;
          b
            ..tx = c.dx + dx * math.cos(w) - dy * math.sin(w)
            ..ty = c.dy + dx * math.sin(w) + dy * math.cos(w);
        } else {
          // Libres: deambulan como enjambre.
          b.tx += math.sin(t * 0.7 + b.seed * 40) * 20 * dt;
          b.ty += math.cos(t * 0.6 + b.seed * 30) * 20 * dt;
        }
      }
      final ax = k * (b.tx - b.x) - c * b.vx + math.sin(t * 3 + b.seed * 50) * 30;
      final ay = k * (b.ty - b.y) - c * b.vy + math.cos(t * 2.6 + b.seed * 70) * 30;
      b
        ..vx += ax * dt
        ..vy += ay * dt
        ..x += b.vx * dt
        ..y += b.vy * dt
        ..alpha += (b.targetAlpha - b.alpha) * (1 - math.exp(-6 * dt))
        ..scale += (b.targetScale - b.scale) * (1 - math.exp(-5 * dt));
    }
    notifyListeners();
  }

  /// Estampa muchas letras en una sola llamada (mucho más liviano que dibujar
  /// cada una por separado). [at] es el centro de cada letra; [size], su tamaño
  /// de fuente. Devuelve false si el atlas aún no está listo.
  bool stampLetters(Canvas canvas, List<({String ch, Offset at, double size, Color color})> letters) {
    final atlas = _atlas;
    if (atlas == null) return false;
    if (letters.isEmpty) return true;
    final transforms = <ui.RSTransform>[], rects = <Rect>[], colors = <Color>[];
    for (final l in letters) {
      transforms.add(ui.RSTransform.fromComponents(
        rotation: 0,
        scale: l.size / atlasFontSize,
        anchorX: _cellW / 2,
        anchorY: _cellH / 2,
        translateX: l.at.dx,
        translateY: l.at.dy,
      ));
      rects.add(_rect(_cellOf(l.ch)));
      colors.add(l.color);
    }
    canvas.drawAtlas(atlas, transforms, rects, colors, BlendMode.modulate, null, Paint());
    return true;
  }

  void _paint(Canvas canvas, {required bool background}) {
    final atlas = _atlas;
    if (atlas == null) return;
    final transforms = <ui.RSTransform>[], rects = <Rect>[], colors = <Color>[];
    for (final b in _bees) {
      final isSphere = b.role == _Role.sphere;
      if (isSphere != background || b.alpha < 0.02) continue;
      transforms.add(ui.RSTransform.fromComponents(
        rotation: 0,
        scale: b.scale,
        anchorX: _cellW / 2,
        anchorY: _cellH / 2,
        translateX: b.x,
        translateY: b.y,
      ));
      rects.add(_rect(b.ch));
      colors.add(Colors.white.withValues(alpha: b.alpha.clamp(0.0, 1.0)));
    }
    if (transforms.isEmpty) return;
    canvas.drawAtlas(atlas, transforms, rects, colors, BlendMode.modulate, null, Paint());
  }
}

/// Dibuja el enjambre. Va una capa encima de toda la app (las letras en vuelo y
/// las que arman textos) y, en la pantalla principal, otra detrás del menú
/// (la esfera). La de encima mueve el enjambre en cada cuadro.
class SwarmView extends StatefulWidget {
  const SwarmView({super.key, this.background = false});

  final bool background;

  @override
  State<SwarmView> createState() => _SwarmViewState();
}

class _SwarmViewState extends State<SwarmView> with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (!widget.background) {
      _ticker = createTicker((d) {
        final dt = ((d - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
        _last = d;
        Swarm.instance.step(dt);
      })
        ..start();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
  }

  /// Dónde empieza esta capa en la pantalla: el enjambre usa coordenadas de
  /// pantalla y la capa de fondo no empieza en la esquina.
  Offset _origin() {
    final box = context.findRenderObject();
    return box is RenderBox && box.attached ? box.localToGlobal(Offset.zero) : Offset.zero;
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(painter: _SwarmPainter(widget.background, _origin), size: Size.infinite),
        ),
      );
}

class _SwarmPainter extends CustomPainter {
  _SwarmPainter(this.background, this.origin) : super(repaint: Swarm.instance);

  final bool background;
  final Offset Function() origin;

  @override
  void paint(Canvas canvas, Size size) {
    final o = origin();
    if (background) {
      // La esfera va centrada en el espacio que le da la pantalla principal.
      Swarm.instance
        ..sphereCenter = o + Offset(size.width / 2, size.height * 0.45)
        ..sphereRadius = size.shortestSide * 0.36;
    }
    canvas.save();
    canvas.translate(-o.dx, -o.dy);
    Swarm.instance._paint(canvas, background: background);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SwarmPainter old) => old.background != background;
}

/// Caracteres visibles de una pantalla, con su lugar en la pantalla.
List<SwarmGlyph> collectGlyphs(BuildContext context, {int max = 600}) {
  final out = <SwarmGlyph>[];
  void visit(RenderObject r) {
    if (out.length >= max) return;
    if (r is RenderParagraph && r.attached && r.hasSize) {
      final text = r.text.toPlainText();
      for (var i = 0; i < text.length && out.length < max; i++) {
        final ch = text[i];
        if (ch.trim().isEmpty) continue;
        final boxes = r.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
        if (boxes.isEmpty) continue;
        final rect = boxes.first.toRect();
        out.add((at: r.localToGlobal(rect.center), ch: ch, height: rect.height));
      }
    }
    r.visitChildren(visit);
  }

  final root = context.findRenderObject();
  if (root != null) visit(root);
  return out;
}
