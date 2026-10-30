import 'dart:async';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../core/app_exception.dart';
import '../domain/library_entry.dart';
import '../domain/study.dart';
import '../domain/summarizer.dart' show studySummaryExtractive;
import '../platform/study_ai.dart';
import '../playback/tts_audio_handler.dart';
import 'swarm_transition.dart';
import 'player_sheets.dart' show downloadSummary;

/// Páginas del documento abierto (o su texto entero como una sola página) y
/// la página que se está leyendo.
(List<String>, int) studySource(TtsAudioHandler handler) {
  final pages = handler.pages.isNotEmpty ? handler.pages : [handler.chunks.map((c) => c.text).join(' ')];
  return (pages, handler.pages.isNotEmpty ? handler.currentChunk?.pageIndex ?? 0 : 0);
}

/// Elige qué parte del documento estudiar.
class StudyScopePicker extends StatelessWidget {
  const StudyScopePicker({super.key, required this.value, required this.onChanged, required this.pageCount});
  final StudyScope value;
  final ValueChanged<StudyScope> onChanged;
  final int pageCount;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    children: [
      for (final s in StudyScope.values)
        if (pageCount > 1 || s == StudyScope.documento)
          ChoiceChip(label: Text(s.label), selected: value == s, onSelected: (_) => onChanged(s)),
    ],
  );
}

/// Resumen con la IA del equipo: por partes, mostrando el avance, y al final
/// conceptos clave, ideas principales y un resumen breve.
Future<void> showStudySummarySheet(BuildContext context, TtsAudioHandler handler, LibraryEntry entry) =>
    showSwarmSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: _StudySummary(handler: handler, entry: entry),
      ),
    ).whenComplete(handler.stopAside);

class _StudySummary extends StatefulWidget {
  const _StudySummary({required this.handler, required this.entry});
  final TtsAudioHandler handler;
  final LibraryEntry entry;

  @override
  State<_StudySummary> createState() => _StudySummaryState();
}

class _StudySummaryState extends State<_StudySummary> {
  final _ai = StudyAi();
  late final (List<String>, int) _source = studySource(widget.handler);
  StudyScope _scope = StudyScope.capitulo;
  bool _running = false;
  bool _closed = false;
  int _done = 0;
  int _total = 0;
  StudySummary? _result;
  String? _error;
  bool _reading = false;

  /// Sin IA en el equipo (Android, iPhone sin Apple Intelligence): el resumen
  /// se arma con las palabras y frases que más pesan en el texto.
  String? _noAi;
  StudyEngine? _engine;
  bool _checked = false;

  /// Sin IA, o con la IA chica de la tablet (no respeta el formato: los
  /// conceptos e ideas salían rotos y tardaba más de un minuto), el resumen
  /// se arma al instante con lo que más pesa en el texto.
  bool get _localOnly => _noAi != null;

  @override
  void initState() {
    super.initState();
    if (_source.$1.length <= 1) _scope = StudyScope.documento;
    _ai.unavailableReason().then((r) async {
      final engine = await _ai.engine();
      if (!mounted) return;
      setState(() {
        _noAi = r;
        _engine = engine;
        _checked = true;
      });
    });
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }

  Future<void> _summarize() async {
    final (pages, current) = _source;
    final (from, to) = studyPages(pages, _scope, current, chapters: widget.handler.chapters);
    final parts = splitForStudy(pages.sublist(from, to).join('\n\n'));
    final outline = studyOutline(pages, from, to, chapters: widget.handler.chapters);
    StudySummary withList(StudySummary r) => outline == null ? r : r.withOutline(outline.$1, outline.$2);
    if (parts.isEmpty) {
      setState(() => _error = 'No hay suficiente texto en esta parte para resumir.');
      return;
    }
    await _run(parts, pages, from, to, withList);
  }

  Future<void> _run(
    List<String> parts,
    List<String> pages,
    int from,
    int to,
    StudySummary Function(StudySummary) withList,
  ) async {
    setState(() {
      _running = true;
      _done = 0;
      _total = parts.length;
      _result = null;
      _error = null;
    });
    if (_localOnly) {
      final text = pages.sublist(from, to).join('\n\n');
      final s = await compute(studySummaryExtractive, text);
      if (_closed) return;
      setState(() {
        _running = false;
        _done = _total;
        _result = s.isEmpty ? null : withList(s);
        if (s.isEmpty) _error = 'El texto es demasiado corto para resumirlo.';
      });
      return;
    }
    final partial = <StudySummary>[];
    String? lastError;
    for (final part in parts) {
      if (_closed) return;
      try {
        final s = await _ai.summarize(part);
        if (!s.isEmpty) partial.add(s);
      } on AppException catch (e) {
        lastError = e.message;
      }
      if (_closed) return;
      setState(() {
        _done++;
        if (partial.isNotEmpty) _result = mergeSummaries(partial);
      });
    }
    StudySummary? overall;
    if (partial.length > 1) {
      // Un resumen breve de todo: se resumen las ideas de cada parte.
      final ideas = partial.expand((p) => p.ideas).join(' ');
      try {
        overall = await _ai.summarize(ideas.length > 3500 ? ideas.substring(0, 3500) : ideas);
      } on AppException {
        overall = null;
      }
    }
    if (_closed) return;
    setState(() {
      _running = false;
      _result = partial.isEmpty ? null : withList(mergeSummaries(partial, overall: overall));
      if (partial.isEmpty) _error = lastError ?? 'No se pudo resumir este texto.';
    });
  }

  Future<void> _listen(List<String> lines) async {
    if (_reading) {
      setState(() => _reading = false);
      await widget.handler.stopAside();
      return;
    }
    setState(() => _reading = true);
    final error = await widget.handler.speakAside(lines);
    if (!mounted) return;
    setState(() => _reading = false);
    if (error != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: SwarmText(error)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final result = _result;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Resumen para estudiar', style: t.titleLarge),
            const SizedBox(height: 4),
            Text(
              !_checked
                  ? ''
                  : !_localOnly
                  ? _engine?.label ?? ''
                  : _noAi == null
                  ? 'Armado al instante con las palabras y frases que más pesan en el texto.'
                  : 'Armado con las palabras y frases que más pesan en el texto. Con IA: $_noAi',
              style: t.bodySmall,
            ),
            const SizedBox(height: 12),
            if (!_running && result == null && _checked) ...[
              StudyScopePicker(
                value: _scope,
                pageCount: _source.$1.length,
                onChanged: (s) => setState(() => _scope = s),
              ),
              if (_scope == StudyScope.documento && _source.$1.length > 30)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Un documento largo puede tardar varios minutos.', style: t.bodySmall),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _summarize,
                icon: const Icon(CupertinoIcons.sparkles),
                label: const Text('Resumir'),
              ),
            ],
            if (_running) ...[
              LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
              const SizedBox(height: 6),
              Text('Leyendo parte ${_done + 1 > _total ? _total : _done + 1} de $_total…', style: t.bodySmall),
              const SizedBox(height: 8),
            ],
            if (_error != null) Text(_error!, style: t.bodyMedium),
            if (result != null) ...[
              Flexible(
                child: SwarmArrival(
                  child: _SummaryView(summary: result, handler: widget.handler, listening: _reading),
                ),
              ),
              if (!_running)
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _listen(result.toLines()),
                      icon: Icon(_reading ? CupertinoIcons.stop_fill : CupertinoIcons.speaker_2),
                      label: Text(_reading ? 'Detener' : 'Escuchar'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => downloadSummary(context, widget.handler, widget.entry, result.toLines()),
                      icon: const Icon(CupertinoIcons.arrow_down_to_line),
                      label: const Text('Descargar'),
                    ),
                    TextButton(onPressed: () => setState(() => _result = null), child: const Text('Otra parte')),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// El resumen en pantalla. Al escucharlo se sigue la lectura como en el
/// documento: lo ya leído en blanco, la frase que suena en blanco con la
/// palabra que suena en amarillo, lo que viene en gris; y se desplaza solo.
class _SummaryView extends StatefulWidget {
  const _SummaryView({required this.summary, required this.handler, required this.listening});
  final StudySummary summary;
  final TtsAudioHandler handler;
  final bool listening;

  @override
  State<_SummaryView> createState() => _SummaryViewState();
}

class _SummaryViewState extends State<_SummaryView> {
  final _keys = <int, GlobalKey>{};
  int? _shown;

  @override
  void initState() {
    super.initState();
    widget.handler.asideIndex.addListener(_follow);
  }

  @override
  void dispose() {
    widget.handler.asideIndex.removeListener(_follow);
    super.dispose();
  }

  void _follow() {
    final i = widget.handler.asideIndex.value;
    if (i == null || i == _shown) return;
    _shown = i;
    final ctx = _keys[i]?.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.3, duration: const Duration(milliseconds: 300));
  }

  /// Una línea del resumen (su lugar en [StudySummary.toLines]).
  Widget _line(int index, InlineSpan Function(TextStyle style) build, TextStyle base) {
    return Padding(
      key: _keys.putIfAbsent(index, GlobalKey.new),
      padding: const EdgeInsets.only(bottom: 8),
      child: ValueListenableBuilder<int?>(
        valueListenable: widget.handler.asideIndex,
        builder: (context, now, _) {
          final upcoming = widget.listening && now != null && index > now;
          final style = upcoming ? base.copyWith(color: base.color?.withValues(alpha: 0.5)) : base;
          if (now != index) return Text.rich(build(style));
          return ValueListenableBuilder<(int, int)?>(
            valueListenable: widget.handler.asideWord,
            builder: (context, word, _) => Text.rich(_withWord(build(style), word)),
          );
        },
      ),
    );
  }

  /// Marca en amarillo la palabra que suena dentro de la línea.
  InlineSpan _withWord(InlineSpan span, (int, int)? word) {
    if (word == null) return span;
    final plain = span.toPlainText();
    final (a, b) = word;
    if (a < 0 || b > plain.length || a >= b) return span;
    final style = span.style;
    // El mismo amarillo que la lectura, más oscuro sobre el fondo blanco.
    final dark = Theme.of(context).brightness == Brightness.dark;
    return TextSpan(
      style: style,
      children: [
        TextSpan(text: plain.substring(0, a)),
        TextSpan(
          text: plain.substring(a, b),
          style: TextStyle(color: dark ? const Color(0xFFFAC775) : const Color(0xFFBA7517)),
        ),
        TextSpan(text: plain.substring(b)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final s = widget.summary;
    final body = (t.bodyLarge ?? const TextStyle()).copyWith(color: Theme.of(context).colorScheme.primary);
    var i = 0;
    final children = <Widget>[];
    if (s.brief.isNotEmpty) {
      children
        ..add(Text('En pocas palabras', style: t.titleMedium))
        ..add(const SizedBox(height: 4))
        ..add(_line(i++, (st) => TextSpan(text: s.brief, style: st), body))
        ..add(const SizedBox(height: 12));
    }
    if (s.concepts.isNotEmpty) {
      i++; // "Conceptos clave." se dice como título
      children.add(Text('Conceptos clave', style: t.titleMedium));
      children.add(const SizedBox(height: 4));
      for (final c in s.concepts) {
        final line = c.meaning.isEmpty ? '${c.term}.' : '${c.term}: ${c.meaning}';
        final bold = c.term.length;
        children.add(
          _line(
            i++,
            (st) => TextSpan(
              style: st,
              children: [
                TextSpan(
                  text: line.substring(0, bold),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: line.substring(bold)),
              ],
            ),
            body,
          ),
        );
      }
      children.add(const SizedBox(height: 8));
    }
    if (s.ideas.isNotEmpty) {
      i++; // "Ideas principales."
      children.add(Text('Ideas principales', style: t.titleMedium));
      children.add(const SizedBox(height: 4));
      for (final idea in s.ideas) {
        children.add(_line(i++, (st) => TextSpan(text: idea, style: st), body));
      }
    }
    if (s.outline.isNotEmpty) {
      i++; // el título de la lista se dice antes
      children
        ..add(const SizedBox(height: 12))
        ..add(Text(s.outlineTitle, style: t.titleMedium))
        ..add(const SizedBox(height: 4));
      for (final o in s.outline) {
        final cut = o.indexOf(' · ');
        // Se dice "Ley 1. Nunca…": misma posición de letras que lo que se ve
        // (" · " y ". " ocupan lo mismo menos uno), así que se muestra igual.
        final shownText = cut < 0 ? '$o.' : '${o.substring(0, cut)}. ${o.substring(cut + 3)}.';
        children.add(
          _line(
            i++,
            (st) => TextSpan(
              style: st,
              children: [
                TextSpan(
                  text: shownText.substring(0, cut < 0 ? shownText.length : cut),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (cut >= 0) TextSpan(text: shownText.substring(cut)),
              ],
            ),
            body,
          ),
        );
      }
    }
    return ListView(shrinkWrap: true, children: [...children, const SizedBox(height: 8)]);
  }
}
