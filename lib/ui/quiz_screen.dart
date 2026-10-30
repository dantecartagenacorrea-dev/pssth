import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../core/app_exception.dart';
import '../data/study_points_store.dart';
import '../domain/library_entry.dart';
import '../domain/quiz_local.dart';
import '../domain/study.dart';
import '../platform/study_ai.dart';
import '../playback/tts_audio_handler.dart';
import 'study_sheets.dart';
import 'swarm_transition.dart';
import 'premium.dart';

/// Preguntas de estudio sobre el documento, al estilo Duolingo: rondas de 10,
/// 30 o 60 preguntas de opción múltiple, niveles básico, medio y experto,
/// puntos que se acumulan y racha de aciertos. Las hace la IA del equipo y
/// cambian en cada ronda.
class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.handler, required this.entry});
  final TtsAudioHandler handler;
  final LibraryEntry entry;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

enum _Stage { setup, playing, done }

class _QuizScreenState extends State<QuizScreen> {
  static const _sizes = [10, 30, 60];

  /// Preguntas que se piden a la IA de una vez (caben en su memoria).
  static const _batch = 5;

  final _ai = StudyAi();
  final _store = StudyPointsStore();
  final _rnd = math.Random();
  late final (List<String>, int) _source = studySource(widget.handler);

  _Stage _stage = _Stage.setup;
  int _size = 10;
  QuizLevel _level = QuizLevel.basico;
  StudyScope _scope = StudyScope.capitulo;
  String? _unavailable;
  StudyEngine? _engine;

  /// Solo preguntas sacadas del texto: sin IA, o con la de la tablet, que es
  /// muy chica para hacerlas bien (copiaba el formato del pedido).
  bool get _localOnly => _unavailable != null;
  bool _checking = true;
  StudyPoints? _points;

  final _questions = <QuizQuestion>[];

  /// Preguntas sin IA que no entraron al empezar: completan la ronda si la IA
  /// no alcanza a hacer todas.
  var _spare = <QuizQuestion>[];

  bool _generating = false;
  String? _genError;
  int _round = 0;
  int _index = 0;
  int? _picked;
  int _correct = 0;
  int _streak = 0;
  int _bestStreak = 0;
  int _earned = 0;

  /// Lee en voz alta cada pregunta, sus opciones y el resultado.
  bool _aloud = true;
  int _spoken = -1;

  @override
  void initState() {
    super.initState();
    if (_source.$1.length <= 1) _scope = StudyScope.documento;
    _init();
  }

  Future<void> _init() async {
    final reason = await _ai.unavailableReason();
    final engine = await _ai.engine();
    final points = await _store.load(widget.entry.id);
    if (!mounted) return;
    setState(() {
      _unavailable = reason;
      _engine = engine;
      _points = points;
      _checking = false;
    });
  }

  @override
  void dispose() {
    _round++; // corta la generación en curso
    unawaited(widget.handler.stopAside());
    super.dispose();
  }

  void _start() {
    final (pages, current) = _source;
    final (from, to) = studyPages(pages, _scope, current, chapters: widget.handler.chapters);
    final text = pages.sublist(from, to).join('\n\n');
    final parts = splitForStudy(text)..shuffle(_rnd);
    // Primero, sin IA y al instante: preguntas sacadas del propio texto, para
    // empezar a responder ya. Sin IA en el equipo, la ronda es solo de estas.
    final local = localQuiz(text, max: _size, rnd: _rnd);
    final first = _localOnly ? _size : (_size / 5).ceil();
    if (parts.isEmpty || (_localOnly && local.isEmpty)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: SwarmText('No hay suficiente texto en esta parte para hacer preguntas.')));
      return;
    }
    setState(() {
      _stage = _Stage.playing;
      _questions.clear();
      _index = 0;
      _spoken = -1;
      _picked = null;
      _correct = 0;
      _streak = 0;
      _bestStreak = 0;
      _earned = 0;
      _genError = null;
      _questions.addAll(local.take(first));
      _spare = local.skip(first).toList();
    });
    final round = ++_round;
    if (_localOnly) {
      setState(() => _generating = false);
      return;
    }
    _generate(parts, round);
  }

  /// Pide preguntas por partes del texto, en tandas, hasta juntar la ronda.
  /// Se puede responder mientras llegan las siguientes.
  Future<void> _generate(List<String> parts, int round) async {
    setState(() => _generating = true);
    final seen = <String>{for (final q in _questions) q.question.toLowerCase()};
    var attempt = _questions.length;
    var failures = 0;
    while (_questions.length < _size && failures < 6 && attempt < _size) {
      final part = parts[attempt % parts.length];
      attempt++;
      try {
        final batch = await _ai.quiz(
          part,
          count: math.min(_batch, _size - _questions.length),
          level: _level,
          rnd: _rnd,
        );
        if (!mounted || round != _round) return;
        final fresh = batch.where((q) => seen.add(q.question.toLowerCase())).take(_size - _questions.length);
        if (fresh.isEmpty) failures++;
        setState(() => _questions.addAll(fresh));
      } on AppException catch (e) {
        if (!mounted || round != _round) return;
        failures++;
        _genError = e.message;
      }
    }
    if (!mounted || round != _round) return;
    setState(() {
      _generating = false;
      // La IA no alcanzó: se completa con las preguntas sacadas del texto.
      _questions.addAll(_spare.where((q) => seen.add(q.question.toLowerCase())).take(_size - _questions.length));
      if (_questions.isNotEmpty && _index >= _questions.length && _picked == null) _stage = _Stage.done;
    });
  }

  Future<void> _answer(int option) async {
    if (_picked != null) return;
    final q = _questions[_index];
    final ok = option == q.answer;
    final streak = ok ? _streak + 1 : 0;
    final points = quizPoints(correct: ok, level: _level, streak: streak);
    setState(() {
      _picked = option;
      _streak = streak;
      if (ok) _correct++;
      _bestStreak = math.max(_bestStreak, streak);
      _earned += points;
    });
    _say(quizAnswerSpeech(q, option));
    final saved = await _store.add(widget.entry.id, points, streak: streak);
    if (mounted) setState(() => _points = saved);
  }

  void _say(List<String> lines) {
    if (_aloud) unawaited(widget.handler.speakAside(lines));
  }

  /// La pregunta que aparece se lee una vez (también la que llega mientras se
  /// esperaba).
  void _sayQuestion() {
    if (_stage != _Stage.playing || _index >= _questions.length || _spoken == _index) return;
    _spoken = _index;
    final q = _questions[_index];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _spoken == _index) _say(quizQuestionSpeech(q));
    });
  }

  void _next() {
    unawaited(widget.handler.stopAside());
    setState(() {
      _picked = null;
      _index++;
      if (_index >= _questions.length && !_generating) _stage = _Stage.done;
    });
  }

  @override
  Widget build(BuildContext context) {
    _sayQuestion();
    return PremiumPage(
      title: 'Preguntas',
      subtitle: switch (_points) {
        final p? => 'Preguntas de estudio · ${p.document} pts',
        null => 'Preguntas de estudio',
      },
      actions: [
        PageAction(
          icon: _aloud ? CupertinoIcons.speaker_2 : CupertinoIcons.speaker_slash,
          tooltip: _aloud ? 'No leer en voz alta' : 'Leer en voz alta',
          onTap: () {
            setState(() => _aloud = !_aloud);
            if (!_aloud) unawaited(widget.handler.stopAside());
          },
        ),
      ],
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: switch (_stage) {
            _Stage.setup => _setup(context),
            _Stage.playing => _playing(context),
            _Stage.done => _done(context),
          },
        ),
      ),
    );
  }

  Widget _setup(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (_checking) return const Center(child: CircularProgressIndicator());
    // Llega después de revisar qué IA hay: se forma con el enjambre.
    return SwarmArrival(
      child: ListView(
        children: [
          Text(widget.entry.name, style: t.titleMedium),
          const SizedBox(height: 4),
          Text(
            _unavailable != null
                ? 'Sin IA: preguntas de completar la frase, sacadas del texto. Para preguntas que lo '
                      'entienden: $_unavailable'
                : _localOnly
                ? 'Preguntas de completar la frase, sacadas del texto al instante. Cambian en cada ronda.'
                : '${_engine?.label ?? ''} Las primeras salen al instante del texto. Cambian en cada ronda.',
            style: t.bodySmall,
          ),
          const SizedBox(height: 20),
          Text('Cuántas preguntas', style: t.titleSmall),
          Wrap(
            spacing: 8,
            children: [
              for (final n in _sizes)
                ChoiceChip(label: Text('$n'), selected: _size == n, onSelected: (_) => setState(() => _size = n)),
            ],
          ),
          const SizedBox(height: 16),
          Text('Nivel', style: t.titleSmall),
          Wrap(
            spacing: 8,
            children: [
              for (final l in QuizLevel.values)
                ChoiceChip(
                  label: Text('${l.label} · ${l.points} pts'),
                  selected: _level == l,
                  onSelected: (_) => setState(() => _level = l),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Sobre qué parte', style: t.titleSmall),
          StudyScopePicker(value: _scope, pageCount: _source.$1.length, onChanged: (s) => setState(() => _scope = s)),
          const SizedBox(height: 24),
          FilledButton.icon(onPressed: _start, icon: const Icon(CupertinoIcons.play_fill), label: const Text('Empezar')),
          if (_points case final p?) ...[
            const SizedBox(height: 24),
            Text('En este documento: ${p.document} puntos · mejor racha ${p.bestStreak}', style: t.bodyMedium),
            Text('Total acumulado: ${p.total} puntos', style: t.bodyMedium),
          ],
        ],
      ),
    );
  }

  Widget _playing(BuildContext context) {
    if (_index >= _questions.length) {
      if (!_generating) {
        return Center(
          child: Text(_genError ?? 'No se pudieron preparar preguntas sobre esta parte.', textAlign: TextAlign.center),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(_questions.isEmpty ? 'Preparando las preguntas…' : 'Preparando más preguntas…'),
          ],
        ),
      );
    }
    final q = _questions[_index];
    final total = _generating ? _size : _questions.length;
    // Cada pregunta nueva se forma con el enjambre.
    return SwarmArrival(key: ValueKey(_index), child: _question(context, q, total));
  }

  Widget _question(BuildContext context, QuizQuestion q, int total) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        LinearProgressIndicator(value: (_index + 1) / total),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('Pregunta ${_index + 1} de $total', style: t.bodySmall),
            const Spacer(),
            if (_streak >= 2) Text('Racha $_streak  ·  ', style: t.bodySmall),
            Text('+$_earned pts', style: t.bodySmall),
          ],
        ),
        const SizedBox(height: 20),
        Text(q.question, style: t.titleLarge),
        const SizedBox(height: 20),
        for (var i = 0; i < q.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.all(16),
                backgroundColor: _picked == null
                    ? null
                    : i == q.answer
                    ? Colors.green.withValues(alpha: 0.25)
                    : i == _picked
                    ? scheme.error.withValues(alpha: 0.25)
                    : null,
              ),
              onPressed: _picked == null ? () => _answer(i) : null,
              child: Text('${'ABCDEF'[i]}) ${q.options[i]}', style: t.bodyLarge),
            ),
          ),
        if (_picked != null) ...[
          const SizedBox(height: 8),
          Text(_picked == q.answer ? '¡Correcto!' : 'No era esa.', style: t.titleMedium),
          if (q.explanation.isNotEmpty) ...[const SizedBox(height: 4), Text(q.explanation, style: t.bodyMedium)],
          const SizedBox(height: 16),
          FilledButton(onPressed: _next, child: const Text('Siguiente')),
        ],
      ],
    );
  }

  Widget _done(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final answered = _questions.length;
    return ListView(
      children: [
        Text('Ronda terminada', style: t.headlineSmall),
        const SizedBox(height: 12),
        Text('$_correct de $answered correctas · nivel ${_level.label}', style: t.titleMedium),
        Text('Ganaste $_earned puntos · mejor racha $_bestStreak', style: t.bodyLarge),
        if (answered < _size)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Esta parte del texto alcanzó para $answered preguntas.', style: t.bodySmall),
          ),
        if (_points case final p?) ...[
          const SizedBox(height: 12),
          Text('En este documento: ${p.document} puntos · total: ${p.total}', style: t.bodyMedium),
        ],
        const SizedBox(height: 24),
        FilledButton(onPressed: () => setState(() => _stage = _Stage.setup), child: const Text('Otra ronda')),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Volver a la lectura')),
      ],
    );
  }
}
