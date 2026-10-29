import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../playback/tts_audio_handler.dart';

/// Un carácter de la pantalla: dónde está (en coordenadas de la pantalla),
/// qué letra es, su tamaño de letra, su color, si va en negrita y, si es un
/// ícono (objeto), la fuente de íconos de donde sale.
typedef SwarmGlyph = ({Offset at, String ch, double size, Color color, bool bold, String? family});

enum _Role { free, text, sphere }

class _Bee {
  _Bee(math.Random r)
      : seed = r.nextDouble(),
        sphereIndex = 0,
        ch = 0;

  final double seed;
  double flow = 0; // cuánto subió por el río (0 abajo, 1 arriba)
  double wait = 0; // segundos que espera su turno antes de volar a su lugar
  double x = 0, y = 0, vx = 0, vy = 0;
  double tx = 0, ty = 0;
  double alpha = 0, targetAlpha = 0;
  double scale = 0.5, targetScale = 0.5;
  Color color = Colors.white;
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

  /// Letras del enjambre: alcanzan para los textos de una pantalla llena.
  static const count = 1400;
  // Todo lo que suele haber en pantalla, para que ningún carácter llegue como
  // un punto y aparezca solo al final.
  static const _chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'
      'ÁÉÍÓÚÑÜáéíóúñüÀÈÌÒÙàèìòùÂÊÎÔÛâêîôûÄËÏÖäëïöÇç'
      '¡!¿?.,:;()[]{}-–—_%«»·•…"\'“”‘’/\\|+=*×÷±≈<>^~#&@\$€°²³√₁₂Δπ';

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

  /// Donde corre el río de letras (la pantalla principal, detrás del menú).
  Rect riverArea = Rect.zero;
  double _time = 0, _energy = 0;
  Offset? _swirl; // centro del remolino mientras carga una pantalla

  /// Íconos (objetos) que aparecieron en pantalla: se dibujan en el atlas
  /// después de las letras, así el enjambre también los forma.
  final _extras = <({String ch, String family})>[];
  final _extraCells = <String, int>{};

  /// Dibuja las letras una vez en una imagen, para estamparlas por cientos:
  /// primero todas en peso normal, después en negrita (títulos) y al final
  /// los íconos que se hayan visto.
  Future<void> init() async {
    await _buildAtlas();
    for (final b in _bees) {
      b.ch = _rnd.nextInt(_chars.length);
    }
    if (!_ready.isCompleted) _ready.complete();
  }

  final _ready = Completer<void>();

  /// Cuánto tarda en salir la última letra de una pantalla (la primera sale
  /// enseguida): la pantalla se escribe en secuencia.
  static const writeDelay = 0.5;

  /// Listo para dibujar (atlas hecho): las pantallas esperan esto para
  /// armarse desde la dispersión y no aparecer ya formadas.
  Future<void> get ready => _ready.future;

  Future<void> _buildAtlas() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    void draw(int i, String ch, TextStyle style) {
      final cell = Rect.fromLTWH((i % _cols) * _cellW, (i ~/ _cols) * _cellH, _cellW, _cellH);
      final tp = TextPainter(text: TextSpan(text: ch, style: style), textDirection: TextDirection.ltr)..layout();
      tp.paint(canvas, cell.center - Offset(tp.width / 2, tp.height / 2));
      tp.dispose();
    }

    for (var w = 0; w < 2; w++) {
      for (var j = 0; j < _chars.length; j++) {
        draw(w * _chars.length + j, _chars[j],
            TextStyle(color: Colors.white, fontSize: atlasFontSize, fontWeight: w == 0 ? FontWeight.w400 : FontWeight.w700));
        if (w == 0) _cells[_chars[j]] = j;
      }
    }
    for (var k = 0; k < _extras.length; k++) {
      final e = _extras[k];
      final i = 2 * _chars.length + k;
      draw(i, e.ch, TextStyle(color: Colors.white, fontSize: atlasFontSize, fontFamily: e.family));
      _extraCells['${e.family}|${e.ch}'] = i;
    }
    final rows = ((2 * _chars.length + _extras.length) / _cols).ceil();
    _atlas = await recorder.endRecording().toImage((_cols * _cellW).ceil(), (rows * _cellH).ceil());
  }

  /// Suma al atlas los íconos de [glyphs] que todavía no tiene (antes de
  /// formarlos, para que no viajen como un punto).
  Future<void> ensure(List<SwarmGlyph> glyphs) async {
    var added = false;
    for (final g in glyphs) {
      final family = g.family;
      if (family == null || _extraCells.containsKey('$family|${g.ch}')) continue;
      if (_extras.any((e) => e.family == family && e.ch == g.ch)) continue;
      _extras.add((ch: g.ch, family: family));
      added = true;
    }
    if (added && _atlas != null) await _buildAtlas();
  }

  // Sin atlas todavía (recién abierta la app) cualquier celda sirve: no se dibuja.
  int _cellOf(String ch, {bool bold = false, String? family}) {
    if (family != null) return _extraCells['$family|$ch'] ?? _cells['·'] ?? 0;
    return (_cells[ch] ?? _cells['·'] ?? 0) + (bold ? _chars.length : 0);
  }

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
  void formText(List<SwarmGlyph> glyphs, {required bool sphere, bool overlay = false}) {
    if (overlay) {
      _formOverlay(glyphs);
      return;
    }
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
    // En orden de lectura (renglón por renglón, de izquierda a derecha): así
    // la pantalla se escribe desde la dispersión, en secuencia.
    final sortedGlyphs = List.of(glyphs.take(n))
      ..sort((a, b) => (a.at.dy - b.at.dy).abs() > 6 ? a.at.dy.compareTo(b.at.dy) : a.at.dx.compareTo(b.at.dx));
    for (var k = 0; k < order.length; k++) {
      final b = _bees[order[k]];
      if (k < n) {
        final g = sortedGlyphs[k];
        b
          ..wait = writeDelay * k / n
          ..role = _Role.text
          ..tx = g.at.dx
          ..ty = g.at.dy
          ..ch = _cellOf(g.ch, bold: g.bold, family: g.family)
          ..color = g.color.withValues(alpha: 1)
          ..targetScale = g.size / atlasFontSize
          ..targetAlpha = g.color.a;
      } else {
        b
          ..color = Colors.white
          ..wait = 0;
        // Al entrar al río, cada letra toma un tramo distinto del cauce.
        if (sphere && b.role != _Role.sphere) b.flow = _rnd.nextDouble();
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

  /// Letras que puede usar un diálogo o panel: todas menos las del río, que
  /// sigue corriendo detrás.
  List<_Bee> _overlayPool() => [for (final b in _bees) if (b.role != _Role.sphere) b]..sort((a, b) => a.y.compareTo(b.y));

  /// Arma el contenido de un diálogo o panel con las letras libres y las del
  /// texto de atrás (que salen de su lugar), en orden de lectura.
  void _formOverlay(List<SwarmGlyph> glyphs) {
    final pool = _overlayPool();
    final n = math.min(glyphs.length, pool.length);
    final sorted = List.of(glyphs.take(n))
      ..sort((a, b) => (a.at.dy - b.at.dy).abs() > 6 ? a.at.dy.compareTo(b.at.dy) : a.at.dx.compareTo(b.at.dx));
    for (var k = 0; k < n; k++) {
      final g = sorted[k];
      final b = pool[k];
      b
        ..role = _Role.text
        ..wait = writeDelay * k / n
        ..tx = g.at.dx
        ..ty = g.at.dy
        ..ch = _cellOf(g.ch, bold: g.bold, family: g.family)
        ..color = g.color.withValues(alpha: 1)
        ..alpha = math.max(b.alpha, 0.4)
        ..targetScale = g.size / atlasFontSize
        ..targetAlpha = g.color.a;
    }
  }

  /// Un diálogo o panel se cierra: sus letras toman el lugar del texto y se
  /// sueltan hacia arriba, apagándose. La pantalla de atrás no se toca.
  void dissolveOverlay(List<SwarmGlyph> glyphs) {
    final pool = _overlayPool();
    final n = math.min(glyphs.length, pool.length);
    for (var k = 0; k < n; k++) {
      final g = glyphs[k];
      final b = pool[k];
      b
        ..role = _Role.free
        ..wait = 0
        ..x = g.at.dx
        ..y = g.at.dy
        ..vx = 0
        ..vy = 0
        ..tx = g.at.dx + (b.seed - 0.5) * 160
        ..ty = g.at.dy - 80 - _rnd.nextDouble() * 160
        ..ch = _cellOf(g.ch, bold: g.bold, family: g.family)
        ..color = g.color.withValues(alpha: 1)
        ..scale = g.size / atlasFontSize
        ..alpha = g.color.a
        ..targetAlpha = 0;
    }
  }

  /// ¿Llegaron las letras a su lugar? (todas a menos de [tolerance] píxeles).
  bool textArrived({double tolerance = 2.5}) {
    for (final b in _bees) {
      if (b.role != _Role.text) continue;
      if ((b.tx - b.x).abs() > tolerance || (b.ty - b.y).abs() > tolerance) return false;
    }
    return true;
  }

  /// El texto real ya se ve: las letras del enjambre se funden en él.
  void settleText() {
    for (final b in _bees) {
      if (b.role == _Role.text) b.targetAlpha = 0;
    }
  }

  /// La pantalla se va: cada carácter que se ve en ella (en [glyphs], donde
  /// está ahora) se vuelve una letra del enjambre en su mismo lugar, así la
  /// pantalla se deshace en sus propias letras. El resto se junta en un
  /// remolino al centro mientras carga la siguiente (nunca queda en negro).
  void liftText(List<SwarmGlyph> glyphs) {
    final view = ui.PlatformDispatcher.instance.views.first;
    final size = view.physicalSize / view.devicePixelRatio;
    final center = Offset(size.width / 2, size.height / 2);
    _swirl = center;
    final n = math.min(glyphs.length, _bees.length);
    for (var i = 0; i < _bees.length; i++) {
      final b = _bees[i];
      if (i < n) {
        final g = glyphs[i];
        b
          ..role = _Role.text
          ..wait = 0
          ..x = g.at.dx
          ..y = g.at.dy
          // Se sueltan apenas: tiemblan en su sitio hasta que la siguiente
          // pantalla las llame.
          ..tx = g.at.dx + (b.seed - 0.5) * 10
          ..ty = g.at.dy + (_rnd.nextDouble() - 0.5) * 10
          ..vx = 0
          ..vy = 0
          ..ch = _cellOf(g.ch, bold: g.bold, family: g.family)
          ..color = g.color.withValues(alpha: 1)
          ..scale = g.size / atlasFontSize
          ..targetScale = g.size / atlasFontSize
          ..alpha = g.color.a
          ..targetAlpha = g.color.a;
        continue;
      }
      if (glyphs.isEmpty && b.role == _Role.text) {
        b
          ..alpha = 1
          ..targetAlpha = 1;
        continue;
      }
      b.color = Colors.white;
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
    // Río de letras: sube suave desde abajo, serpentea y se arremolina. Con
    // la voz corre más rápido y los remolinos giran más.
    final area = riverArea.isEmpty ? Offset(sphereCenter.dx - sphereRadius * 1.4, 0) & Size(sphereRadius * 2.8, sphereCenter.dy * 2) : riverArea;
    final speed = 0.035 + 0.12 * _energy; // fracción del alto por segundo
    final eddies = [
      for (var e = 0; e < 3; e++)
        Offset(
          area.center.dx + math.sin(t * 0.21 + e * 2.1) * area.width * 0.12,
          area.bottom - ((t * 0.025 + e / 3) % 1) * area.height,
        ),
    ];
    final eddyRadius = area.width * 0.16;
    const k = 55.0, c = 11.0; // resorte y freno: llegan rápido sin rebotar de más
    for (final b in _bees) {
      if (b.role == _Role.sphere) {
        final before = b.flow;
        b.flow = (b.flow + dt * speed * (0.6 + 0.8 * b.seed)) % 1;
        final y = area.bottom - b.flow * area.height;
        final v = (area.bottom - y) / area.height; // 0 abajo, 1 arriba
        final lane = b.seed * 2 - 1; // lugar a lo ancho del cauce
        final width = area.width * (0.16 + 0.06 * math.sin(t * 0.3 + v * 4));
        final meander = math.sin(v * 5 + t * 0.45) * area.width * 0.13 + math.sin(v * 11 - t * 0.8) * area.width * 0.03;
        var x = area.center.dx + meander + lane * width;
        var yy = y;
        // Remolinos: las letras cercanas giran alrededor de cada uno.
        for (final e in eddies) {
          final dx = x - e.dx, dy = yy - e.dy;
          final d2 = dx * dx + dy * dy;
          final a = (0.9 + 2.2 * _energy) * math.exp(-d2 / (eddyRadius * eddyRadius));
          if (a < 0.01) continue;
          final ca = math.cos(a), sa = math.sin(a);
          x = e.dx + dx * ca - dy * sa;
          yy = e.dy + dx * sa + dy * ca;
        }
        b
          ..tx = x
          ..ty = yy
          // Aparece abajo, se apaga arriba; tenue para que el menú se vea.
          ..targetAlpha = (0.08 + 0.42 * math.sin(math.pi * v)) * (1 - 0.4 * lane.abs())
          ..targetScale = 0.16 + 0.22 * math.sin(math.pi * v);
        if (b.flow < before) {
          // Volvió a nacer abajo: sin cruzar la pantalla volando.
          b
            ..x = x
            ..y = yy
            ..alpha = 0;
        }
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
      // Mientras espera su turno no la atrae su lugar: sigue flotando.
      final pull = b.wait > 0 ? 0.0 : k;
      if (b.wait > 0) b.wait -= dt;
      final ax = pull * (b.tx - b.x) - c * b.vx + math.sin(t * 3 + b.seed * 50) * 30;
      final ay = pull * (b.ty - b.y) - c * b.vy + math.cos(t * 2.6 + b.seed * 70) * 30;
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
      colors.add(b.color.withValues(alpha: b.alpha.clamp(0.0, 1.0)));
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
        ..sphereRadius = size.shortestSide * 0.36
        ..riverArea = o & size;
    }
    canvas.save();
    canvas.translate(-o.dx, -o.dy);
    Swarm.instance._paint(canvas, background: background);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SwarmPainter old) => old.background != background;
}

/// Estilo efectivo de cada carácter de un párrafo (los tramos heredan el
/// estilo de los de afuera), alineado con `toPlainText()`.
List<TextStyle?> _charStyles(InlineSpan root) {
  final out = <TextStyle?>[];
  void walk(InlineSpan span, TextStyle? inherited) {
    final style = inherited == null ? span.style : inherited.merge(span.style);
    if (span is TextSpan) {
      final text = span.text;
      if (text != null) out.addAll(List.filled(text.length, style));
      for (final c in span.children ?? const <InlineSpan>[]) {
        walk(c, style);
      }
    } else {
      out.add(style); // un widget dentro del texto ocupa un carácter
    }
  }

  walk(root, null);
  return out;
}

/// Caracteres visibles de una pantalla, con su lugar, tamaño, color y peso.
/// Los íconos también (con su fuente, para formarlos como objetos); el texto
/// transparente no.
List<SwarmGlyph> collectGlyphs(BuildContext context, {int max = Swarm.count}) {
  final out = <SwarmGlyph>[];
  final view = ui.PlatformDispatcher.instance.views.first;
  final screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
  void visit(RenderObject r) {
    if (out.length >= max) return;
    if (r is RenderParagraph && r.attached && r.hasSize) {
      final text = r.text.toPlainText();
      final styles = _charStyles(r.text);
      for (var i = 0; i < text.length && out.length < max; i++) {
        final ch = text[i];
        if (ch.trim().isEmpty) continue;
        final style = i < styles.length ? styles[i] : null;
        final family = style?.fontFamily;
        final isIcon = family != null && family.contains('Icons');
        final color = style?.color ?? Colors.white;
        if (color.a < 0.05) continue;
        final boxes = r.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
        if (boxes.isEmpty) continue;
        final at = r.localToGlobal(boxes.first.toRect().center);
        if (!screen.contains(at)) continue; // fuera de la vista (listas largas)
        out.add((
          at: at,
          ch: ch,
          size: r.textScaler.scale(style?.fontSize ?? 14),
          color: color,
          bold: (style?.fontWeight?.value ?? 400) >= 600,
          family: isIcon ? family : null,
        ));
      }
    }
    r.visitChildren(visit);
  }

  final root = context.findRenderObject();
  if (root != null) visit(root);
  return out;
}
