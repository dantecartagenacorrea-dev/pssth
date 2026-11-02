import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';

import '../domain/math/formula.dart' show formatNumber, parseFormula, readingsDiffer;
import '../domain/math/rational.dart' show MathError;
import '../domain/math/solver.dart';
import '../domain/math/stacked_math.dart';
import 'exercise_photo.dart';
import 'formula_model_offer.dart';
import 'math_graph_view.dart';
import '../ocr/ocr_engine.dart' show OcrUnavailable;
import '../data/model_store.dart';
import '../platform/formula_model_reader.dart';
import '../platform/fraction_reader.dart';
import '../platform/native_text.dart';
import '../playback/tts_audio_handler.dart';
import 'swarm_transition.dart';

/// Resolver ejercicios de matemáticas del colegio con un motor exacto (no con
/// la IA, que se equivoca en las cuentas): cuentas, ecuaciones de 1.º y 2.º
/// grado, regla de tres y sistemas de dos ecuaciones, con los pasos
/// explicados y para escuchar. Se escribe con un teclado matemático o se
/// lee de una foto y se corrige antes de resolver.
class MathSolveView extends StatefulWidget {
  const MathSolveView({super.key, required this.handler, this.modelStore, this.onGraph});
  final TtsAudioHandler handler;

  /// Para el lector de fórmulas opcional; sin él se usa solo el lector común.
  final ModelStore? modelStore;

  /// Lleva una fórmula a Graficar.
  final void Function(String formula)? onGraph;

  @override
  State<MathSolveView> createState() => _MathSolveViewState();
}

class _MathSolveViewState extends State<MathSolveView> {
  static const _keys = ['x', 'y', '²', '^', '√', '(', ')', '÷', '×', '−', '+', '=', '%', ',', 'nueva línea'];
  static const _examples = ['2x + 3 = 11', 'x² − 5x + 6 = 0', '3/5 = 12/x', '1/2 + 1/3 × 6', 'x + y = 5\nx − y = 1'];

  final _text = TextEditingController();
  final _focus = FocusNode();
  MathSolution? _solution;
  String? _error;
  String? _notice;

  /// Lo que se encontró en una foto con varios ejercicios: se toca uno.
  List<String> _choices = const [];

  /// «y = 2x + 1» no se resuelve: se grafica.
  String? _toGraph;
  bool _reading = false;
  bool _busy = false;
  bool _showSteps = false;
  SystemMethod _method = SystemMethod.sustitucion;

  @override
  void initState() {
    super.initState();
    _text.addListener(_onText); // vista previa de lo que se entendió
  }

  void _onText() => setState(() {});

  @override
  void dispose() {
    widget.handler.stopAside();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _insert(String key) {
    final value = key == 'nueva línea' ? '\n' : key;
    final sel = _text.selection;
    final start = sel.isValid ? sel.start : _text.text.length;
    final end = sel.isValid ? sel.end : _text.text.length;
    _text.value = TextEditingValue(
      text: _text.text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length),
    );
  }

  void _solve() {
    setState(() {
      _notice = null;
      _toGraph = null;
      if (widget.onGraph != null && RegExp(r'^\s*(y|f\(x\))\s*=', caseSensitive: false).hasMatch(_text.text)) {
        final formula = formulaLinesIn(_text.text);
        if (formula.length == 1) {
          _solution = null;
          _error = null;
          _toGraph = formula.single;
          _notice = 'Esto es una fórmula: en vez de resolverla, se puede graficar.';
          return;
        }
      }
      try {
        _solution = solveMath(_text.text, method: _method);
        _showSteps = false;
        _error = null;
      } on MathError catch (e) {
        _solution = null;
        // Lo que no se resuelve con pasos, si es una cuenta con funciones, tiene
        // resultado igual (sen(30) + 1).
        final value = _withFunctions(_text.text);
        _error = value == null ? e.message : null;
        _notice = value == null
            ? null
            : 'Resultado: $value (ángulos en grados). Esta cuenta no tiene pasos explicados.';
      }
    });
  }

  String? _withFunctions(String text) {
    try {
      final formula = parseFormula(text, degrees: true);
      final value = formula.at();
      return formula.usesX || !value.isFinite ? null : formatNumber(value);
    } on MathError {
      return null;
    }
  }

  void _choose(String line) {
    _text.text = line;
    _choices = const [];
    _solve();
  }

  Future<void> _photo(ImageSource source) async {
    final photo = await takeExercisePhoto(context, source);
    if (photo == null || !mounted) return;
    setState(() => _busy = true);
    try {
      var read = await _read(photo.path);
      // Si en el recuadro no quedó el ejercicio, se busca en la foto entera.
      final full = photo.full;
      if (read.lines.isEmpty && full != null) read = await _read(full);
      if (mounted) _showRead(read.text, read.lines, doubt: read.doubt);
    } on OcrUnavailable {
      if (mounted) setState(() => _error = 'Este equipo no puede leer texto de fotos.');
    } on PlatformException {
      if (mounted) setState(() => _error = 'No se pudo leer la foto. Prueba con otra más nítida.');
    } finally {
      if (mounted) setState(() => _busy = false);
      await deleteExercisePhoto(photo);
    }
  }

  /// Lo que dice la foto y los ejercicios que hay en ella.
  Future<({String text, List<String> lines, bool doubt})> _read(String path) async {
    final native = NativeText();
    final text = await native.recognize(path, languageCorrection: false, minimumTextHeight: 0.01);
    var lines = mathLinesIn(text);
    // Un ejercicio suelto lo lee mejor el lector de fórmulas, si está. Con
    // enunciados o varios renglones no sirve: lee una sola fórmula por foto.
    final store = widget.modelStore;
    if (store != null && lines.length <= 1 && !hasWords(text)) {
      final reading = await FormulaModelReader(store).readChecked(path, (await native.recognizeLines(path)).lines);
      final found = reading.plain == null ? const <String>[] : mathLinesIn(reading.plain!);
      final checked = reading.check == null ? const <String>[] : mathLinesIn(reading.check!);
      // Una cifra o un signo mal leídos darían otro resultado sin avisar: lo que
      // se lee entero se compara con lo que se lee número por número.
      if (found.length == 1 && checked.length == 1 && readingsDiffer(found.single, checked.single)) {
        return (text: text, lines: [found.single, checked.single], doubt: true);
      }
      // Sin fracciones leídas, una raya de más no dice nada: puede ser un menos.
      final fractionsRead = found.isEmpty ? 0 : '/'.allMatches(found.first).length;
      final mismatch = reading.fractions > 0 && fractionsRead > 0 && fractionsRead != reading.fractions;
      if (checked.length == 1 && (found.isEmpty || mismatch)) {
        lines = checked; // armó mal las fracciones: la foto tiene otras rayas
      } else if (found.isNotEmpty && !mismatch) {
        lines = found;
      } else if (found.isNotEmpty) {
        // No coincide con las rayas de la foto y no hay con qué compararlo.
        return (text: found.first, lines: const <String>[], doubt: false);
      }
    }
    if (lines.isEmpty) {
      // Una fracción apilada se lee como renglones sueltos: hay que armarla.
      final stacked =
          stackedMath((await native.recognizeLines(path)).lines) ?? await readStackedFractions(path, native);
      if (stacked != null) lines = mathLinesIn(stacked);
    }
    return (text: text, lines: lines, doubt: false);
  }

  /// Un solo ejercicio (o las dos ecuaciones de un sistema) se resuelve de una;
  /// con varios se elige; si no se entiende, lo leído queda para corregirlo.
  void _showRead(String text, List<String> lines, {bool doubt = false}) {
    setState(() {
      _solution = null;
      _choices = const [];
      _notice = null;
      // Las fracciones apiladas se leen aparte: puede haberlas sin texto común.
      if (text.trim().isEmpty && lines.isEmpty) {
        _error = 'No se encontró texto en la foto. Prueba con más luz o más cerca.';
      } else if (lines.isEmpty) {
        _text.text = text.trim();
        _error = 'No entendí lo que leí. Corrígelo arriba y toca Resolver.';
      } else if (doubt) {
        _text.clear();
        _error = null;
        _choices = lines;
        _notice = 'Se puede leer de dos formas. Mira la foto y toca la correcta.';
      } else if (lines.length > 1 && !(lines.length == 2 && lines.every((l) => l.contains('=')))) {
        _text.clear();
        _error = null;
        _choices = lines;
        _notice = 'Encontré varios ejercicios: toca el que quieres resolver.';
      } else {
        _text.text = lines.join('\n');
        _error = null;
      }
    });
    if (lines.isNotEmpty && _choices.isEmpty) _solve();
  }

  Future<void> _listen(MathSolution s) async {
    if (_reading) {
      setState(() => _reading = false);
      await widget.handler.stopAside();
      return;
    }
    setState(() => _reading = true);
    final error = await widget.handler.speakAside(s.spoken());
    if (!mounted) return;
    setState(() => _reading = false);
    if (error != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: SwarmText(error)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final solution = _solution;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Cuentas, ecuaciones de 1.º y 2.º grado, regla de tres y sistemas de dos ecuaciones (una por línea).',
          style: t.bodySmall,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _text,
          focusNode: _focus,
          minLines: 1,
          maxLines: 4,
          style: t.titleLarge,
          keyboardType: TextInputType.multiline,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: '2x + 3 = 11',
            suffixIcon: IconButton(
              tooltip: 'Borrar',
              icon: const Icon(CupertinoIcons.xmark_circle),
              onPressed: () => setState(() {
                _text.clear();
                _solution = null;
                _error = null;
                _notice = null;
              }),
            ),
          ),
        ),
        // Lo que la app entendió, bien escrito (como en una hoja).
        if (previewLatex(_text.text) case final tex?)
          Padding(padding: const EdgeInsets.only(top: 12), child: _Formula(tex, size: 26)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final k in _keys)
              ActionChip(
                label: k == 'nueva línea'
                    ? const Icon(CupertinoIcons.arrow_turn_down_left, size: 18)
                    : Text(k, style: t.titleMedium),
                tooltip: k == 'nueva línea' ? 'Otra ecuación (para un sistema)' : null,
                onPressed: () => _insert(k),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : _solve,
                icon: const Icon(CupertinoIcons.number),
                label: const Text('Resolver'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: 'Foto del ejercicio',
              onPressed: _busy ? null : () => _photo(ImageSource.camera),
              icon: const Icon(CupertinoIcons.camera),
            ),
            IconButton.outlined(
              tooltip: 'Desde Fotos',
              onPressed: _busy ? null : () => _photo(ImageSource.gallery),
              icon: const Icon(CupertinoIcons.photo_on_rectangle),
            ),
          ],
        ),
        if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_notice!, style: t.bodyMedium),
          ),
        if (_toGraph case final formula?)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton.tonal(
              onPressed: () => widget.onGraph?.call(formula),
              child: const Text('Ver el gráfico'),
            ),
          ),
        if (_choices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final c in _choices) ActionChip(label: Text(c), onPressed: () => _choose(c))],
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: t.bodyLarge?.copyWith(color: scheme.error)),
          ),
        if (widget.modelStore case final store?)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: FormulaModelOffer(store: store),
          ),
        if (solution == null && _error == null) ...[
          const SizedBox(height: 20),
          Text('Ejemplos', style: t.titleSmall),
          Wrap(
            spacing: 6,
            children: [
              for (final e in _examples)
                ActionChip(label: Text(e.replaceAll('\n', ' ; ')), onPressed: () => setState(() => _text.text = e)),
            ],
          ),
        ],
        if (solution != null) ...[
          const SizedBox(height: 20),
          // Tarjeta de solución, como en las apps de matemáticas: el
          // ejercicio bien escrito, la respuesta grande y los pasos a pedido.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('PASOS DE LA SOLUCIÓN', style: t.labelSmall),
                  const SizedBox(height: 6),
                  Text(solution.kind, style: t.titleMedium),
                  const SizedBox(height: 12),
                  _Formula(solution.problemLatex, size: 24),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Icon(CupertinoIcons.arrow_down, size: 20),
                  ),
                  Container(
                    padding: const EdgeInsets.only(left: 12),
                    decoration: BoxDecoration(
                      border: Border(left: BorderSide(color: scheme.primary, width: 4)),
                    ),
                    child: switch (solution.answerLatex) {
                      final tex? => _Formula(tex, size: 30),
                      null => Text(solution.answer, style: t.titleLarge),
                    },
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => setState(() => _showSteps = !_showSteps),
                        icon: Icon(_showSteps ? CupertinoIcons.chevron_up : CupertinoIcons.arrow_right),
                        label: Text(_showSteps ? 'Ocultar los pasos' : 'Mostrar los pasos'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _listen(solution),
                        icon: Icon(_reading ? CupertinoIcons.stop_fill : CupertinoIcons.speaker_2),
                        label: Text(_reading ? 'Detener' : 'Escuchar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (solution.isSystem) ...[
            const SizedBox(height: 8),
            // Como en clase: el mismo sistema por el método que pida el profesor.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in SystemMethod.values)
                  ChoiceChip(
                    label: Text(m.short),
                    selected: _method == m,
                    onSelected: (_) {
                      _method = m;
                      _solve();
                    },
                  ),
              ],
            ),
          ],
          if (_showSteps)
            for (final (i, s) in solution.steps.indexed.skip(1))
              Card(
                child: ListTile(
                  title: Text('$i. ${s.note}', style: t.bodyMedium),
                  subtitle: s.math.isEmpty
                      ? null
                      : Padding(padding: const EdgeInsets.only(top: 8), child: _Formula(s.latex, size: 22)),
                ),
              ),
          if (solution.graph case final g?)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('GRÁFICO', style: t.labelSmall),
                    const SizedBox(height: 8),
                    MathGraphView(graph: g),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Una fórmula dibujada como en un cuaderno (fracciones apiladas, exponentes
/// arriba). Si es más ancha que la pantalla, se desliza de lado.
class _Formula extends StatelessWidget {
  const _Formula(this.tex, {required this.size});
  final String tex;
  final double size;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Math.tex(
      tex,
      textStyle: TextStyle(fontSize: size, color: Theme.of(context).colorScheme.onSurface),
      onErrorFallback: (_) => Text(tex, style: TextStyle(fontSize: size * 0.7)),
    ),
  );
}
