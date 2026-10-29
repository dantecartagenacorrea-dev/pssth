import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../domain/word_timing.dart';
import '../playback/tts_audio_handler.dart';
import 'glyph_dust.dart';
import 'swarm.dart';

/// Texto "en el éter": al llegar un fragmento sus letras aparecen dispersas y
/// se ordenan; las palabras que faltan flotan más cuanto más lejos están de la
/// lectura, la que suena se enciende y las ya leídas quedan quietas. Con
/// "Reducir movimiento" las letras no flotan y solo se enciende la palabra.
class EtherText extends StatefulWidget {
  const EtherText({super.key, required this.handler, required this.text, this.style, this.relation = 0});

  final TtsAudioHandler handler;
  final String text;
  final TextStyle? style;

  /// Posición respecto al fragmento que suena: negativa si ya se leyó (letras
  /// quietas), 0 si es el que suena y positiva si todavía no llega (1 es el
  /// siguiente, que empieza a escribirse antes de que termine el actual).
  final int relation;

  @override
  State<EtherText> createState() => _EtherTextState();
}

/// Ritmo de la voz, compartido entre fragmentos: así el siguiente sabe cuándo
/// empezar a escribirse.
class _ReadingClock {
  /// Las letras terminan de formarse este tiempo antes de que llegue la voz.
  static const lead = 1.5;

  /// Lo que tarda una letra en juntarse desde el polvo.
  static const forming = 1.3;

  static double wordsPerSecond = 2.8;

  /// Palabras que le quedan al fragmento que suena.
  static int remaining = 1 << 20;

  /// Palabras por delante de la voz que ya deben estar escribiéndose.
  static int get ahead => ((lead + forming) * wordsPerSecond).round();
}

/// Palabras pasadas el adelanto que ya se dibujan como polvo.
const _nearWords = 6;

class _EtherTextState extends State<EtherText> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _scene = _EtherScene();
  final _rnd = math.Random();
  Duration _last = Duration.zero;
  bool _still = false;
  List<int> _wordOf = const []; // palabra de cada carácter (-1 si es espacio)
  int _wordCount = 0;
  int? _lastWord;
  double _lastWordAt = 0;
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
    _wordCount = spans.length;
    _scene.reset(text.length, _rnd);
  }

  /// Mide el ritmo de la voz (palabras por segundo) y cuántas le quedan.
  void _followVoice(int? cur) {
    _ReadingClock.remaining = _wordCount - (cur ?? 0);
    if (cur == null || cur == _lastWord) return;
    final last = _lastWord;
    final elapsed = _scene.time - _lastWordAt;
    _lastWord = cur;
    _lastWordAt = _scene.time;
    if (last == null || cur <= last || elapsed < 0.05 || elapsed > 3) return;
    final rate = ((cur - last) / elapsed).clamp(1.0, 6.0);
    _ReadingClock.wordsPerSecond = _ReadingClock.wordsPerSecond * 0.8 + rate * 0.2;
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
    final playing = _h.snapshot.value.playing;
    // Antes de la primera palabra informada, la voz está al comienzo.
    final cur = _currentWord() ?? (widget.relation == 0 && playing ? 0 : null);
    if (widget.relation == 0) _followVoice(cur);
    final ahead = _ReadingClock.ahead;
    final p = _scene.particles;
    for (var i = 0; i < p.length; i++) {
      final c = p[i];
      final w = i < _wordOf.length ? _wordOf[i] : -1;
      final dist = switch (widget.relation) {
        < 0 => -1,
        1 => w < 0 ? null : _ReadingClock.remaining + w,
        > 1 => w < 0 ? null : 1 << 20,
        _ => w < 0 ? null : w - (cur ?? -1),
      };
      // Escrita por adelantado: ya formada, esperando a la voz. El fragmento que
      // suena está escrito entero (también en pausa) para poder seguirlo.
      final written = dist != null && dist > 0 && (widget.relation == 0 || dist <= ahead);
      final far = dist == null ? 0.0 : math.min(1.0, (dist - ahead) / 10);
      double amp;
      double pull;
      if (dist == null) {
        amp = playing ? 3 : 1.5;
        pull = 4;
      } else if (dist < 0) {
        amp = 0.4;
        pull = 10;
      } else if (dist == 0 || written) {
        amp = 1.2;
        pull = 12;
      } else {
        amp = 8 + 42 * far;
        pull = 2 + (1 - far) * 4;
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
      final chaosTarget = _still || written || (dist != null && dist <= 0)
          ? 0.0
          : dist == null
              ? 0.08
              : 0.35 + 0.65 * far;
      c.chaos += (chaosTarget - c.chaos) * (1 - math.exp(-(chaosTarget < c.chaos ? 2.5 : 1.2) * dt));
      // Ya formada (escrita por adelantado, sonando o leída), la letra se
      // vuelve sólida y así queda.
      final solidTarget = c.chaos < 0.04 && (dist == null || dist <= ahead || written) ? 1.0 : 0.0;
      c.solid += (solidTarget - c.solid) * (1 - math.exp(-(solidTarget > 0 ? 6 : 2) * dt));
      c.near = dist != null && dist <= ahead + _nearWords && c.solid < 0.98;
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
  /// Cerca de la voz: se dibuja como polvo. Lejos, como letra entera que flota
  /// (mucho más liviano: un párrafo largo en polvo son decenas de miles de puntos).
  bool near = true;
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
  List<Offset?>? _center;

  TextPainter _glyph(String ch, double alpha, bool glowing) {
    final level = (alpha.clamp(0.0, 1.0) * _levels).round();
    return _glyphs.putIfAbsent((ch, level, glowing), () {
      final color = (glowing ? glow : base).withValues(alpha: level / _levels);
      return TextPainter(
        text: TextSpan(
          text: ch,
          style: style.copyWith(
            color: color,
            shadows: glowing ? [Shadow(color: glow.withValues(alpha: level / _levels), blurRadius: 5)] : null,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
    });
  }

  /// Lugar de cada letra dentro del párrafo ya ordenado.
  /// Centro de cada letra en el párrafo ordenado (para estamparla del atlas).
  List<Offset?> _centers() => _center ??= [
        for (var i = 0; i < text.length; i++)
          text[i].trim().isEmpty
              ? null
              : layout.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1)).firstOrNull?.toRect().center,
      ];

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
  final _bits = <({int letter, String ch, double ox, double oy, double a, double b, double rot, Rect keep, bool absorb})>[];
  final _bitGlyphs = <(String, int, bool), TextPainter>{};

  static const _debrisPool = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  static const _shardW = 5.0, _shardH = 6.0;

  void _buildDust() {
    final homes = _homes();
    final r = math.Random(text.hashCode);
    final xs = <double>[], ys = <double>[], letterOf = <int>[], groupOf = <int>[];
    final gx = <double>[], gy = <double>[], ga = <double>[], gb = <double>[], gr = <double>[], gl = <int>[];
    void group(int letter, double cx, double cy) {
      gl.add(letter);
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
          group(i, home.dx + (col + 0.5) * _shardW, home.dy + (row + 0.5) * _shardH);
          return gx.length - 1;
        });
        xs.add(home.dx + dots[j]);
        ys.add(home.dy + dots[j + 1]);
        letterOf.add(i);
        groupOf.add(g);
      }
      // Una letra o número roto por letra viaja en la corriente: la mayoría
      // desemboca en su letra, como el agua que se junta en el río; el resto
      // no lo alcanza el imán y sube.
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
        absorb: r.nextDouble() < 0.75,
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
      if (!c.near) {
        _bucket[d] = _hidden;
        continue;
      }
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
        // Del documento a la letra: sube por su cauce y llega a su lugar.
        final f = _channel(cx, cy, ga, gb, _progress(kd, gb, t));
        x += f.dx - cx + math.sin(t * 2 + gb * 6.283) * 3 * kd;
        y += f.dy - cy;
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
      ..strokeCap = StrokeCap.square
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
          // Halo sin desenfoque (el desenfoque por punto era lo más caro de
          // dibujar): un punto redondo más grande y tenue detrás.
          Paint()
            ..strokeCap = StrokeCap.round
            ..strokeWidth = 4.5
            ..color = glow.withValues(alpha: 0.22 * level),
        );
      }
      canvas.drawRawPoints(PointMode.points, points, dot..color = (glowing ? glow : base).withValues(alpha: level));
    }
    // Sin líneas: solo se ven las letras en camino a su lugar.
    _paintBits(canvas);
    // Encima, las letras enteras: las ya solidificadas y las lejanas a la voz,
    // que flotan desordenadas hasta que les toca volverse polvo.
    // Las que brillan van con su propio dibujo (llevan halo); las demás se
    // estampan juntas desde el atlas del enjambre, en una sola llamada.
    final homes = _homes();
    final centers = _centers();
    final fontSize = (style.fontSize ?? 16) * scaler.scale(1);
    final stamped = <({String ch, Offset at, double size, Color color})>[];
    for (var i = 0; i < p.length && i < text.length; i++) {
      final c = p[i];
      final home = homes[i], center = centers[i];
      final weight = c.near ? c.solid : 1.0;
      if (home == null || center == null || weight < 0.02) continue;
      final glowing = c.glow > 0.05;
      final alpha = glowing
          ? math.min(1.0, 0.55 + c.glow)
          : (0.35 + 0.6 * c.lit) * (c.near ? 1 : 1 - 0.45 * c.chaos);
      final f = c.near ? 0.5 : 1.0;
      final shift = Offset(c.dx * f, c.dy * f - 3 * c.glow);
      if (glowing) {
        _glyph(text[i], alpha * weight, glowing).paint(canvas, home + shift);
      } else {
        stamped.add((ch: text[i], at: center + shift, size: fontSize, color: base.withValues(alpha: (alpha * weight).clamp(0.0, 1.0))));
      }
    }
    if (!Swarm.instance.stampLetters(canvas, stamped)) {
      for (var j = 0; j < stamped.length; j++) {
        // Sin atlas todavía (primer cuadro): letra por letra.
        final l = stamped[j];
        final tp = _glyph(l.ch, l.color.a, false);
        tp.paint(canvas, l.at - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  /// Cuánto lleva recorrido un trozo (0 en el documento, 1 en su letra). Lejos
  /// de leerse, la corriente no para: los trozos suben un tramo y vuelven a
  /// salir del documento, como un río que corre.
  static double _progress(double kd, double gb, double t) {
    final stream = ((t * 0.07 + gb) % 1) * 0.35;
    final u = math.max(1 - kd, stream * kd);
    return u * u * (3 - 2 * u);
  }

  /// Cauce de un trozo: sale de abajo (el documento), sube casi recto y gira
  /// hacia su letra; muchos cauces así se juntan como los ríos de un delta al
  /// revés. [u] 0 = en el documento, 1 = en la letra (tx, ty).
  Offset _channel(double tx, double ty, double ga, double gb, double u) {
    final sx = layout.width * (ga + 1) / 2;
    final sy = ty + 380 + gb * 420;
    final h = sy - ty;
    final m = 1 - u;
    final a = m * m * m, b = 3 * m * m * u, c = 3 * m * u * u, d = u * u * u;
    return Offset(
      a * sx + b * sx + c * tx + d * tx,
      a * sy + b * (sy - h * 0.55) + c * (ty + h * 0.45) + d * ty,
    );
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
      if (!c.near) continue;
      final k = c.chaos;
      final glowing = c.glow > 0.05;
      // Los que desembocan en la letra siguen visibles hasta casi el final y se
      // funden cuando la letra se solidifica; los demás se apagan al subir.
      final presence = bit.absorb ? math.min(1.0, k * 4) * (1 - c.solid) : math.min(1.0, k * 1.4);
      final alpha = presence * (glowing ? 0.9 : 0.55 + 0.3 * c.lit);
      final level = (alpha.clamp(0.0, 1.0) * _levels).round();
      if (level == 0) continue;
      final e = k * k;
      final drift = ((t * (10 + 30 * bit.b) + bit.b * 200) % 80) - 40;
      final bend = k * (1 - k) * 4;
      // Río: lejos corre en vetas; a medio camino serpentea; al final se junta.
      var x = home.dx + c.dx * 0.5 + e * (bit.a * bit.a * bit.a * 160 + drift) +
          bend * math.cos(home.dx * 0.05 + t * 2.2 + bit.b * 6.283) * 10;
      var y = home.dy + c.dy * 0.5 + e * (bit.a * 12 + (bit.b - 0.5) * 20) +
          bend * math.sin(home.dx * 0.04 + t * 1.8 + bit.a * 6.283) * 16;
      if (bit.absorb) {
        // Sale del documento y desemboca en su letra por su cauce.
        final f = _channel(home.dx, home.dy, bit.a, bit.b, _progress(k, bit.b, t));
        x = f.dx + c.dx * 0.5 + bit.ox * k * 0.3;
        y = f.dy + c.dy * 0.5;
      } else {
        // El imán no lo atrapa: cuando su letra se forma, sube y se desvanece.
        final rise = 1 - k;
        x += bit.ox + rise * math.sin(t * 1.3 + bit.b * 6.283) * 12;
        y += bit.oy - math.pow(rise, 1.5) * (120 + 80 * bit.b);
      }
      final glyph = _bitGlyph(bit.ch, level, glowing);
      final w = glyph.width, h = glyph.height;
      // Al juntarse se encoge hasta el tamaño de un trazo de la letra.
      final scale = bit.absorb ? 0.55 + 0.45 * k : 1.0;
      canvas
        ..save()
        ..translate(x + w / 2, y + h / 2)
        ..scale(scale)
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
