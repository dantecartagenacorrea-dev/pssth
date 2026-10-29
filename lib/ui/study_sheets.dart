import 'package:flutter/material.dart';

import '../core/app_exception.dart';
import '../domain/library_entry.dart';
import '../domain/study.dart';
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
      builder: (_) => SafeArea(child: _StudySummary(handler: handler, entry: entry)),
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

  @override
  void initState() {
    super.initState();
    if (_source.$1.length <= 1) _scope = StudyScope.documento;
  }

  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }

  Future<void> _summarize() async {
    final (pages, current) = _source;
    final (from, to) = studyPages(pages, _scope, current);
    final parts = splitForStudy(pages.sublist(from, to).join('\n\n'));
    if (parts.isEmpty) {
      setState(() => _error = 'No hay suficiente texto en esta parte para resumir.');
      return;
    }
    setState(() {
      _running = true;
      _done = 0;
      _total = parts.length;
      _result = null;
      _error = null;
    });
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
      _result = partial.isEmpty ? null : mergeSummaries(partial, overall: overall);
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
    if (error != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
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
            Text('Hecho por la IA de tu iPhone, sin salir del equipo.', style: t.bodySmall),
            const SizedBox(height: 12),
            if (!_running && result == null) ...[
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
              FilledButton.icon(onPressed: _summarize, icon: const Icon(Icons.auto_awesome), label: const Text('Resumir')),
            ],
            if (_running) ...[
              LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
              const SizedBox(height: 6),
              Text('Leyendo parte ${_done + 1 > _total ? _total : _done + 1} de $_total…', style: t.bodySmall),
              const SizedBox(height: 8),
            ],
            if (_error != null) Text(_error!, style: t.bodyMedium),
            if (result != null) ...[
              Flexible(child: _SummaryView(summary: result)),
              if (!_running)
                Wrap(
                  spacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: () => _listen(result.toLines()),
                      icon: Icon(_reading ? Icons.stop : Icons.volume_up),
                      label: Text(_reading ? 'Detener' : 'Escuchar'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => downloadSummary(context, widget.handler, widget.entry, result.toLines()),
                      icon: const Icon(Icons.download),
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

class _SummaryView extends StatelessWidget {
  const _SummaryView({required this.summary});
  final StudySummary summary;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      shrinkWrap: true,
      children: [
        if (summary.brief.isNotEmpty) ...[
          Text('En pocas palabras', style: t.titleMedium),
          const SizedBox(height: 4),
          Text(summary.brief, style: t.bodyLarge),
          const SizedBox(height: 16),
        ],
        if (summary.concepts.isNotEmpty) ...[
          Text('Conceptos clave', style: t.titleMedium),
          const SizedBox(height: 4),
          for (final c in summary.concepts)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text.rich(TextSpan(children: [
                TextSpan(text: c.term, style: const TextStyle(fontWeight: FontWeight.bold)),
                if (c.meaning.isNotEmpty) TextSpan(text: ': ${c.meaning}'),
              ]), style: t.bodyLarge),
            ),
          const SizedBox(height: 8),
        ],
        if (summary.ideas.isNotEmpty) ...[
          Text('Ideas principales', style: t.titleMedium),
          const SizedBox(height: 4),
          for (final i in summary.ideas)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('• $i', style: t.bodyLarge),
            ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}
