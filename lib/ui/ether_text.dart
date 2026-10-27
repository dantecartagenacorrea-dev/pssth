import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../domain/word_timing.dart';
import '../playback/tts_audio_handler.dart';
import 'glyph_dust.dart';

/// Texto "en el éter": al llegar un fragmento sus letras aparecen dispersas y
/// se ordenan; las palabras que faltan flotan más cuanto más lejos están de la
/// lectura, la que suena se enciende y las ya leídas quedan quietas. Con
/// "Reducir movimiento" las letras no flotan y solo se enciende la palabra.
class EtherText extends StatefulWidget {
  const EtherText({super.key, required this.handler, required this.text, this.style, this.relation = 0});

  final TtsAudioHandler handler;
  final String text;
  final TextStyle? style;

  /// -1 si el fragmento ya se leyó (letras quietas), 0 si es el que suena y
  /// 1 si todavía no llega (todas sus letras en pleno desorden).
  final int relation;

  @override
  State<EtherText> createState() => _EtherTextState();
}

class _EtherTextState extends State<EtherText> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _scene = _EtherScene();
  final _rnd = math.Random();
  Duration _last = Duration.zero;
  bool _still = false;
  List<int> _wordOf = const []; // palabra de cada carácter (-1 si es espacio)
  String? _dustFor; // texto y estilo cuyas letras de polvo ya se pidieron
  bool _dustReady = false;

  TtsAudioHandler get _h => widget.handler;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(EtherText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _prepare();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context);
    if (!_ticker.isActive) _ticker.start();
  }

  void _prepare() {
    final text = widget.text;
    final word = List.filled(text.length, -1);
    final spans = wordSpans(text);
    for (var w = 0; w < spans.length; w++) {
      for (var i = spans[w].$1; i < spans[w].$2; i++) {
        word[i] = w;
      }
    }
    _wordOf = word;
    _scene.reset(text.length, _rnd);
  }

  /// Palabra que suena ahora, o null si la voz no informa (o no coincide).
  int? _currentWord() {
    final range = _h.wordRange.value;
    if (range == null || _h.currentChunk?.speech != widget.text) return null;
    if (range.$1 < 0 || range.$1 >= _wordOf.length) return null;
    final w = _wordOf[range.$1];
    return w < 0 ? null : w;
  }

  void _tick(Duration now) {
    final dt = ((now - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = now;
    _scene.time += dt;
    final cur = _currentWord();
    final playing = _h.snapshot.value.playing;
    final p = _scene.particles;
    for (var i = 0; i < p.length; i++) {
      final c = p[i];
      final w = i < _wordOf.length ? _wordOf[i] : -1;
      final dist = switch (widget.relation) {
        < 0 => -1,
        > 0 => w < 0 ? null : 10,
        _ => cur == null || w < 0 ? null : w - cur,
      };
      double amp;
      double pull;
      if (dist == null) {
        amp = playing ? 3 : 1.5;
        pull = 4;
      } else if (dist < 0) {
        amp = 0.4;
        pull = 10;
      } else if (dist == 0) {
        amp = 1.2;
        pull = 12;
      } else {
        final k = math.min(1.0, dist / 10);
        amp = 8 + 42 * k;
        pull = 2 + (1 - k) * 4;
      }
      if (_still) amp = 0;
      final t = _scene.time * c.speed + c.phase;
      final tx = math.sin(t) * amp;
      final ty = math.cos(t * 0.8) * amp * 0.8;
      final f = 1 - math.exp(-pull * dt);
      c.dx += (tx - c.dx) * f;
      c.dy += (ty - c.dy) * f;
      final glowTarget = dist == 0 ? 1.0 : 0.0;
      c.glow += (glowTarget - c.glow) * (1 - math.exp(-(glowTarget > 0 ? 18 : 3) * dt));
      final litTarget = dist == null || dist <= 0 ? 1.0 : 0.0;
      c.lit += (litTarget - c.lit) * (1 - math.exp(-4 * dt));
      // Cuánto se deshace la letra en polvo: se junta de golpe al leerse y se
      // dispersa despacio.
      final chaosTarget = _still || (dist != null && dist <= 0)
          ? 0.0
          : dist == null
              ? 0.08
              : 0.35 + 0.65 * math.min(1.0, dist / 10);
      c.chaos += (chaosTarget - c.chaos) * (1 - math.exp(-(chaosTarget < c.chaos ? 2.5 : 1.2) * dt));
      // Ya formada y leída (o sonando), la letra se vuelve sólida y así queda.
      final solidTarget = c.chaos < 0.04 && (dist == null || dist <= 0) ? 1.0 : 0.0;
      c.solid += (solidTarget - c.solid) * (1 - math.exp(-(solidTarget > 0 ? 6 : 2) * dt));
    }
    _scene.notify();
  }

  /// Pide los puntos de polvo de las letras; hasta tenerlos se dibujan enteras.
  void _loadDust(TextStyle style, TextScaler scaler) {
    final key = '${widget.text}|$style|${scaler.scale(1)}';
    if (key == _dustFor) return;
    _dustFor = key;
    _dustReady = false;
    GlyphDust.load(widget.text, style, scaler).then((_) {
      if (mounted && _dustFor == key) setState(() => _dustReady = true);
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scene.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = widget.style ?? theme.textTheme.titleLarge ?? const TextStyle();
    final dark = theme.brightness == Brightness.dark;
    final scaler = MediaQuery.textScalerOf(context);
    _loadDust(style, scaler);
    return Semantics(
      label: widget.text,
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, box) {
          final layout = TextPainter(
            text: TextSpan(text: widget.text, style: style),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
          )..layout(maxWidth: box.maxWidth);
          return CustomPaint(
            size: Size(box.maxWidth, layout.height),
            painter: _EtherPainter(
              scene: _scene,
              text: widget.text,
              layout: layout,
              style: style,
              base: style.color ?? theme.colorScheme.onSurface,
              glow: dark ? const Color(0xFFFAC775) : const Color(0xFFBA7517),
              scaler: scaler,
              dust: _dustReady,
            ),
          );
        },
      ),
    );
  }
}

class _Particle {
  _Particle(math.Random r)
      : phase = r.nextDouble() * 2 * math.pi,
        speed = 0.5 + r.nextDouble(),
        dx = (r.nextDouble() - 0.5) * 520,
        dy = (r.nextDouble() - 0.5) * 420;

  final double phase;
  final double speed;
  double dx; // desplazamiento desde su lugar en el texto
  double dy;
  double glow = 0;
  double lit = 0;
  double chaos = 1;
  double solid = 0;
}

class _EtherScene extends ChangeNotifier {
  List<_Particle> particles = const [];
  double time = 0;

  /// Letras nuevas, dispersas lejos de su lugar (la "entropía" inicial).
  void reset(int count, math.Random r) => particles = [for (var i = 0; i < count; i++) _Particle(r)];

  void notify() => notifyListeners();
}

class _EtherPainter extends CustomPainter {
  _EtherPainter({
    required this.scene,
    required this.text,
    required this.layout,
    required this.style,
    required this.base,
    required this.glow,
    required this.scaler,
    required this.dust,
  })  : debrisStyle = debrisOf(style),
        super(repaint: scene);

  /// Letras y números rotos: casi del tamaño del texto, para que se reconozcan.
  static TextStyle debrisOf(TextStyle s) => s.copyWith(fontSize: (s.fontSize ?? 16) * 0.85, fontWeight: FontWeight.w600);

  final _EtherScene scene;
  final String text;
  final TextPainter layout;
  final TextStyle style;
  final Color base;
  final Color glow;
  final TextScaler scaler;
  final bool dust;
  final TextStyle debrisStyle;

  // Letras ya maquetadas por (carácter, nivel de brillo); el brillo se reparte
  // en pocos niveles para no maquetar cientos de letras en cada cuadro.
  static const _levels = 8;
  final _glyphs = <(String, int, bool), TextPainter>{};
  List<Offset?>? _home;

  TextPainter _glyph(String ch, double alpha, bool glowing) {
    final level = (alpha.clamp(0.0, 1.0) * _levels).round();
    return _glyphs.putIfAbsent((ch, level, glowing), () {
      final color = (glowing ? glow : base).withValues(alpha: level / _levels);
      return TextPainter(
        text: TextSpan(
          text: ch,
          style: style.copyWith(
            color: color,
            shadows: glowing ? [Shadow(color: glow.withValues(alpha: level / _levels), blurRadius: 12)] : null,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
    });
  }

  /// Lugar de cada letra dentro del párrafo ya ordenado.
  List<Offset?> _homes() => _home ??= [
        for (var i = 0; i < text.length; i++)
          text[i].trim().isEmpty
              ? null
              : layout.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1)).firstOrNull?.toRect().topLeft,
      ];

  @override
  void paint(Canvas canvas, Size size) {
    if (dust) {
      _paintDust(canvas);
      return;
    }
    final homes = _homes();
    final p = scene.particles;
    for (var i = 0; i < homes.length && i < p.length; i++) {
      final home = homes[i];
      if (home == null) continue;
      final c = p[i];
      final glowing = c.glow > 0.05;
      final alpha = glowing ? math.min(1.0, 0.55 + c.glow) : 0.35 + 0.6 * c.lit;
      _glyph(text[i], alpha, glowing).paint(canvas, home + Offset(c.dx, c.dy - 3 * c.glow));
    }
  }

  // Polvo de cada letra, en trozos: la letra rota en pedacitos (que giran y
  // viajan juntos) y, alrededor, letras y números rotos que corren con ella y
  // se funden en su forma al leerse.
  Float32List? _dotX;
  late Float32List _dotY, _gx, _gy, _ga, _gb, _gr, _px, _py, _buffer;
  late Int32List _letterOf, _groupOf;
  late Uint8List _bucket;

  // Letras y números rotos: un trozo sólido de un carácter al azar, que gira
  // y viaja junto a cada letra hasta fundirse en ella.
  final _bits = <({int letter, String ch, double ox, double oy, double a, double b, double rot, Rect keep})>[];
  final _bitGlyphs = <(String, int, bool), TextPainter>{};

  static const _debrisPool = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const _shardW = 5.0, _shardH = 6.0;

  void _buildDust() {
    final homes = _homes();
    final r = math.Random(text.hashCode);
    final xs = <double>[], ys = <double>[], letterOf = <int>[], groupOf = <int>[];
    final gx = <double>[], gy = <double>[], ga = <double>[], gb = <double>[], gr = <double>[];
    void group(double cx, double cy) {
      gx.add(cx);
      gy.add(cy);
      ga.add(r.nextDouble() * 2 - 1);
      gb.add(r.nextDouble());
      gr.add((r.nextDouble() * 2 - 1) * math.pi);
    }

    for (var i = 0; i < text.length; i++) {
      final home = homes[i];
      final dots = home == null ? null : GlyphDust.of(text[i], style, scaler);
      if (home == null || dots == null) continue;
      // Trozos de la propia letra: cada celda pequeña es un pedazo rígido.
      final shards = <int, int>{};
      for (var j = 0; j < dots.length; j += 2) {
        final col = dots[j] ~/ _shardW, row = dots[j + 1] ~/ _shardH;
        final g = shards.putIfAbsent(col * 64 + row, () {
          group(home.dx + (col + 0.5) * _shardW, home.dy + (row + 0.5) * _shardH);
          return gx.length - 1;
        });
        xs.add(home.dx + dots[j]);
        ys.add(home.dy + dots[j + 1]);
        letterOf.add(i);
        groupOf.add(g);
      }
      // Una letra o número roto acompaña a cada dos letras en la corriente.
      if (i.isOdd) continue;
      final cut = r.nextInt(4); // qué lado se rompió
      final part = 0.45 + r.nextDouble() * 0.3;
      _bits.add((
        letter: i,
        ch: _debrisPool[r.nextInt(_debrisPool.length)],
        ox: (r.nextDouble() - 0.5) * 30,
        oy: (r.nextDouble() - 0.3) * 22,
        a: r.nextDouble() * 2 - 1,
        b: r.nextDouble(),
        rot: (r.nextDouble() * 2 - 1) * math.pi,
        keep: switch (cut) {
          0 => Rect.fromLTRB(0, 0, 1, part),
          1 => Rect.fromLTRB(0, 1 - part, 1, 1),
          2 => Rect.fromLTRB(0, 0, part, 1),
          _ => Rect.fromLTRB(1 - part, 0, 1, 1),
        },
      ));
    }
    final n = xs.length;
    _dotX = Float32List.fromList(xs);
    _dotY = Float32List.fromList(ys);
    _letterOf = Int32List.fromList(letterOf);
    _groupOf = Int32List.fromList(groupOf);
    _gx = Float32List.fromList(gx);
    _gy = Float32List.fromList(gy);
    _ga = Float32List.fromList(ga);
    _gb = Float32List.fromList(gb);
    _gr = Float32List.fromList(gr);
    _px = Float32List(n);
    _py = Float32List(n);
    _bucket = Uint8List(n);
    _buffer = Float32List(n * 2);
  }

  static const _buckets = (_levels + 1) * 2; // brillo × (normal, encendida)
  static const _hidden = 255;

  void _paintDust(Canvas canvas) {
    if (_dotX == null) _buildDust();
    final dotX = _dotX!;
    final p = scene.particles;
    final t = scene.time;
    final counts = Int32List(_buckets);
    // 1) Dónde va cada punto y con qué color.
    for (var d = 0; d < dotX.length; d++) {
      final i = _letterOf[d];
      if (i >= p.length) {
        _bucket[d] = _hidden;
        continue;
      }
      final c = p[i];
      final k = c.chaos;
      final glowing = c.glow > 0.05;
      var alpha = glowing ? math.min(1.0, 0.6 + c.glow) : (0.35 + 0.6 * c.lit) * (1 - 0.45 * k);
      alpha *= 1 - c.solid;
      final level = (alpha.clamp(0.0, 1.0) * _levels).round();
      if (level == 0) {
        _bucket[d] = _hidden;
        continue;
      }
      final b = level + (glowing ? _levels + 1 : 0);
      _bucket[d] = b;
      counts[b]++;
      var x = dotX[d] + c.dx * 0.5, y = _dotY[d] + c.dy * 0.5 - 3 * c.glow;
      final g = _groupOf[d];
      final ga = _ga[g], gb = _gb[g];
      // Cada trozo se suelta a su turno: unos llegan antes que otros.
      final kd = (k * 1.6 - gb * 0.6).clamp(0.0, 1.0);
      if (kd > 0) {
        // El trozo gira sobre sí mismo y se endereza al llegar.
        final ang = kd * _gr[g] + math.sin(t * 0.8 + gb * 6.283) * 0.3 * kd;
        final cs = math.cos(ang), sn = math.sin(ang);
        final cx = _gx[g] + c.dx * 0.5, cy = _gy[g] + c.dy * 0.5;
        final rx = x - cx, ry = y - cy;
        x = cx + rx * cs - ry * sn;
        y = cy + rx * sn + ry * cs;
        // Imán: cuanto más cerca, más rápido cae en su lugar.
        final e = kd * kd;
        // Río: lejos, los trozos corren en vetas de viento hacia los lados.
        final drift = ((t * (10 + 30 * gb) + gb * 200) % 80) - 40;
        x += e * (ga * ga * ga * 160 + drift);
        y += e * (ga * 12 + (gb - 0.5) * 20);
        // A medio camino la corriente serpentea antes de llegar.
        final bend = kd * (1 - kd) * 4;
        x += bend * math.cos(_gx[g] * 0.05 + t * 2.2 + gb * 6.283) * 10;
        y += bend * math.sin(_gx[g] * 0.04 + t * 1.8 + ga * 6.283) * 16;
      }
      _px[d] = x;
      _py[d] = y;
    }
    // 2) Se agrupan por color para dibujarlos en pocas pasadas.
    final offset = Int32List(_buckets + 1);
    for (var b = 0; b < _buckets; b++) {
      offset[b + 1] = offset[b] + counts[b];
    }
    final fill = Int32List.fromList(offset.sublist(0, _buckets));
    for (var d = 0; d < dotX.length; d++) {
      final b = _bucket[d];
      if (b == _hidden) continue;
      final at = fill[b]++ * 2;
      _buffer[at] = _px[d];
      _buffer[at + 1] = _py[d];
    }
    final dot = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.4;
    for (var b = 0; b < _buckets; b++) {
      if (counts[b] == 0) continue;
      final glowing = b > _levels;
      final level = (glowing ? b - _levels - 1 : b) / _levels;
      final points = Float32List.sublistView(_buffer, offset[b] * 2, offset[b + 1] * 2);
      if (glowing) {
        canvas.drawRawPoints(
          PointMode.points,
          points,
          Paint()
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 3
            ..color = glow.withValues(alpha: 0.35 * level)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }
      canvas.drawRawPoints(PointMode.points, points, dot..color = (glowing ? glow : base).withValues(alpha: level));
    }
    _paintBits(canvas);
    // Encima, las letras que ya se solidificaron.
    final homes = _homes();
    for (var i = 0; i < p.length && i < text.length; i++) {
      final c = p[i];
      final home = homes[i];
      if (home == null || c.solid < 0.02) continue;
      final glowing = c.glow > 0.05;
      final alpha = glowing ? math.min(1.0, 0.55 + c.glow) : 0.35 + 0.6 * c.lit;
      _glyph(text[i], alpha * c.solid, glowing).paint(canvas, home + Offset(c.dx * 0.5, c.dy * 0.5 - 3 * c.glow));
    }
  }

  TextPainter _bitGlyph(String ch, int level, bool glowing) => _bitGlyphs.putIfAbsent((ch, level, glowing), () {
        return TextPainter(
          text: TextSpan(text: ch, style: debrisStyle.copyWith(color: (glowing ? glow : base).withValues(alpha: level / _levels))),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();
      });

  /// Las letras y números rotos: viajan con la corriente mientras su letra está
  /// desordenada y se apagan al fundirse en ella.
  void _paintBits(Canvas canvas) {
    final homes = _homes();
    final p = scene.particles;
    final t = scene.time;
    for (final bit in _bits) {
      if (bit.letter >= p.length) continue;
      final home = homes[bit.letter];
      if (home == null) continue;
      final c = p[bit.letter];
      final k = c.chaos;
      final glowing = c.glow > 0.05;
      final alpha = math.min(1.0, k * 1.4) * (glowing ? 0.9 : 0.55 + 0.3 * c.lit);
      final level = (alpha.clamp(0.0, 1.0) * _levels).round();
      if (level == 0) continue;
      final e = k * k;
      final drift = ((t * (10 + 30 * bit.b) + bit.b * 200) % 80) - 40;
      final bend = k * (1 - k) * 4;
      final x = home.dx + bit.ox * k + c.dx * 0.5 + e * (bit.a * bit.a * bit.a * 160 + drift) +
          bend * math.cos(home.dx * 0.05 + t * 2.2 + bit.b * 6.283) * 10;
      final y = home.dy + bit.oy * k + c.dy * 0.5 + e * (bit.a * 12 + (bit.b - 0.5) * 20) +
          bend * math.sin(home.dx * 0.04 + t * 1.8 + bit.a * 6.283) * 16;
      final glyph = _bitGlyph(bit.ch, level, glowing);
      final w = glyph.width, h = glyph.height;
      canvas
        ..save()
        ..translate(x + w / 2, y + h / 2)
        ..rotate(k * bit.rot + math.sin(t * 0.8 + bit.b * 6.283) * 0.3 * k)
        ..clipRect(Rect.fromLTRB(
          -w / 2 + bit.keep.left * w,
          -h / 2 + bit.keep.top * h,
          -w / 2 + bit.keep.right * w,
          -h / 2 + bit.keep.bottom * h,
        ));
      glyph.paint(canvas, Offset(-w / 2, -h / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_EtherPainter old) =>
      old.text != text || old.style != style || old.base != base || old.layout.width != layout.width || old.dust != dust;
}
