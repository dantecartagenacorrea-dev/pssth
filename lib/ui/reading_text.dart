import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../domain/caps_speech.dart';
import '../domain/word_timing.dart';
import '../playback/tts_audio_handler.dart';

/// Texto que se lee, con un barrido suave que sigue a la voz: la palabra que
/// suena en amarillo, las anteriores se apagan de a poco y una marca pequeña
/// se desliza debajo al ritmo de la lectura.
class ReadingText extends StatefulWidget {
  const ReadingText({super.key, required this.handler, required this.text, this.style, this.relation = 0});

  final TtsAudioHandler handler;
  final String text;
  final TextStyle? style;

  /// Posición respecto al fragmento que suena: 0 si es el que suena.
  final int relation;

  @override
  State<ReadingText> createState() => _ReadingTextState();
}

/// Cuánto brilla una palabra según cuántas atrás está de la que suena.
const _trail = [1.0, 0.5, 0.22, 0.0];

class _ReadingTextState extends State<ReadingText> with SingleTickerProviderStateMixin {
  List<(int, int)> _spans = const []; // inicio y fin de cada palabra
  List<int> _wordOf = const []; // palabra de cada carácter (-1 si es espacio)

  /// Paso de una palabra a la siguiente (0 recién cambió, 1 ya asentada).
  late final _step = AnimationController(vsync: this, duration: const Duration(milliseconds: 220), value: 1);
  final _paragraph = GlobalKey();

  int? _word; // palabra que suena
  int? _from; // la que sonaba antes

  TtsAudioHandler get _h => widget.handler;

  @override
  void initState() {
    super.initState();
    _prepare();
    _word = _currentWord();
    _h.wordRange.addListener(_follow);
  }

  @override
  void didUpdateWidget(ReadingText old) {
    super.didUpdateWidget(old);
    if (old.handler != widget.handler) {
      old.handler.wordRange.removeListener(_follow);
      _h.wordRange.addListener(_follow);
    }
    if (old.text != widget.text) {
      _prepare();
      _word = _from = null;
    }
    // Ya se está reconstruyendo: basta con ponerse al día, sin animar.
    final w = _currentWord();
    if (w != _word) {
      _from = null;
      _word = w;
      _step.value = 1;
    }
  }

  @override
  void dispose() {
    _h.wordRange.removeListener(_follow);
    _step.dispose();
    super.dispose();
  }

  void _prepare() {
    final word = List.filled(widget.text.length, -1);
    final spans = wordSpans(widget.text);
    for (var w = 0; w < spans.length; w++) {
      for (var i = spans[w].$1; i < spans[w].$2; i++) {
        word[i] = w;
      }
    }
    _spans = spans;
    _wordOf = word;
  }

  /// Palabra que suena ahora, o null si la voz no informa (o no coincide).
  int? _currentWord() {
    if (widget.relation != 0) return null;
    final range = _h.wordRange.value;
    final speech = _h.currentChunk?.speech;
    if (range == null || speech == null || !sameSpokenText(speech, widget.text)) return null;
    if (range.$1 < 0 || range.$1 >= _wordOf.length) return null;
    final w = _wordOf[range.$1];
    return w < 0 ? null : w;
  }

  /// La voz pasó a otra palabra: el barrido y la marca van tras ella.
  void _follow() {
    final w = _currentWord();
    if (w == _word || !mounted) return;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    setState(() {
      _from = _word;
      _word = w;
    });
    if (w != null && _from != null && !still) {
      _step.forward(from: 0);
    } else {
      _step.value = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = widget.style ?? theme.textTheme.titleLarge ?? const TextStyle();
    final glow = theme.brightness == Brightness.dark ? const Color(0xFFFAC775) : const Color(0xFFBA7517);
    final word = _word;
    if (word == null) return Text(widget.text, style: style);
    final ink = style.color ?? DefaultTextStyle.of(context).style.color ?? theme.colorScheme.onSurface;
    return CustomPaint(
      foregroundPainter: _Mark(
        paragraph: _paragraph,
        from: _from == null ? null : _spans[_from!],
        to: _spans[word],
        step: _step,
        color: glow,
      ),
      child: AnimatedBuilder(
        animation: _step,
        builder: (context, _) => Text.rich(key: _paragraph, _sweep(word, style, ink, glow)),
      ),
    );
  }

  /// El texto con la palabra que suena encendida y la estela de las anteriores.
  TextSpan _sweep(int word, TextStyle style, Color ink, Color glow) {
    final text = widget.text;
    // Solo al avanzar de a una palabra la estela se apaga de forma continua.
    final t = _from == word - 1 ? Curves.easeOut.transform(_step.value) : 1.0;
    final children = <TextSpan>[];
    var at = 0;
    for (var w = word < _trail.length ? 0 : word - (_trail.length - 1); w <= word; w++) {
      final back = word - w;
      final level = back == 0 ? 1.0 : _trail[back - 1] + (_trail[back] - _trail[back - 1]) * t;
      final (a, b) = _spans[w];
      if (a > at) children.add(TextSpan(text: text.substring(at, a)));
      children.add(
        TextSpan(
          text: text.substring(a, b),
          style: level <= 0 ? null : TextStyle(color: Color.lerp(ink, glow, level)),
        ),
      );
      at = b;
    }
    if (at < text.length) children.add(TextSpan(text: text.substring(at)));
    return TextSpan(style: style, children: children);
  }
}

/// La marca pequeña bajo la palabra que suena: se desliza de una palabra a la
/// otra en el mismo renglón y, al cambiar de renglón, se apaga y aparece.
class _Mark extends CustomPainter {
  _Mark({required this.paragraph, required this.from, required this.to, required this.step, required this.color})
    : super(repaint: step);

  final GlobalKey paragraph;
  final (int, int)? from;
  final (int, int) to;
  final Animation<double> step;
  final Color color;

  Rect? _under(RenderParagraph box, (int, int) span) {
    final boxes = box.getBoxesForSelection(TextSelection(baseOffset: span.$1, extentOffset: span.$2));
    if (boxes.isEmpty) return null;
    final r = boxes.first.toRect();
    return Rect.fromCenter(
      center: Offset(r.center.dx, r.bottom - 1.5),
      width: (r.width * 0.6).clamp(6.0, 22.0),
      height: 2.5,
    );
  }

  void _draw(Canvas canvas, Rect r, double opacity) => canvas.drawRRect(
    RRect.fromRectAndRadius(r, const Radius.circular(2)),
    Paint()..color = color.withValues(alpha: 0.9 * opacity),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final box = paragraph.currentContext?.findRenderObject();
    if (box is! RenderParagraph) return;
    final b = _under(box, to);
    if (b == null) return;
    final a = from == null ? null : _under(box, from!);
    final t = Curves.easeOutCubic.transform(step.value);
    if (a == null) {
      _draw(canvas, b, 1);
    } else if ((a.top - b.top).abs() < 1) {
      _draw(canvas, Rect.lerp(a, b, t)!, 1);
    } else {
      if (t < 1) _draw(canvas, a, 1 - t);
      _draw(canvas, b, t);
    }
  }

  @override
  bool shouldRepaint(_Mark old) => old.from != from || old.to != to || old.color != color;
}
