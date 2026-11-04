import 'package:flutter/material.dart';

import '../domain/caps_speech.dart';
import '../domain/word_timing.dart';
import '../playback/tts_audio_handler.dart';

/// Texto que se lee, con la palabra que suena en amarillo.
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

class _ReadingTextState extends State<ReadingText> {
  List<int> _wordOf = const []; // palabra de cada carácter (-1 si es espacio)

  TtsAudioHandler get _h => widget.handler;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void didUpdateWidget(ReadingText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _prepare();
  }

  void _prepare() {
    final word = List.filled(widget.text.length, -1);
    final spans = wordSpans(widget.text);
    for (var w = 0; w < spans.length; w++) {
      for (var i = spans[w].$1; i < spans[w].$2; i++) {
        word[i] = w;
      }
    }
    _wordOf = word;
  }

  /// Palabra que suena ahora, o null si la voz no informa (o no coincide).
  int? _currentWord() {
    final range = _h.wordRange.value;
    final speech = _h.currentChunk?.speech;
    if (range == null || speech == null || !sameSpokenText(speech, widget.text)) return null;
    if (range.$1 < 0 || range.$1 >= _wordOf.length) return null;
    final w = _wordOf[range.$1];
    return w < 0 ? null : w;
  }

  /// Dónde está la palabra [w] dentro del texto.
  (int, int)? _wordSpan(int w) {
    final start = _wordOf.indexOf(w);
    if (start < 0) return null;
    var end = start;
    while (end < _wordOf.length && _wordOf[end] == w) {
      end++;
    }
    return (start, end);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = widget.style ?? theme.textTheme.titleLarge ?? const TextStyle();
    final glow = theme.brightness == Brightness.dark ? const Color(0xFFFAC775) : const Color(0xFFBA7517);
    return ValueListenableBuilder<(int, int)?>(
      valueListenable: _h.wordRange,
      builder: (context, _, _) {
        final text = widget.text;
        final word = widget.relation == 0 ? _currentWord() : null;
        final span = word == null ? null : _wordSpan(word);
        if (span == null) return Text(text, style: style);
        final (a, b) = span;
        return Text.rich(
          TextSpan(
            style: style,
            children: [
              TextSpan(text: text.substring(0, a)),
              TextSpan(
                text: text.substring(a, b),
                style: TextStyle(color: glow),
              ),
              TextSpan(text: text.substring(b)),
            ],
          ),
        );
      },
    );
  }
}
