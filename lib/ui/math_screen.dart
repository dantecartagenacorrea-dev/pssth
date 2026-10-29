import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';

import '../domain/math/rational.dart' show MathError;
import '../domain/math/solver.dart';
import 'math_camera_screen.dart';
import 'math_graph_view.dart';
import '../ocr/ocr_engine.dart' show OcrUnavailable;
import '../platform/native_text.dart';
import '../playback/tts_audio_handler.dart';

/// Resolver ejercicios de matemáticas del colegio con un motor exacto (no con
/// la IA, que se equivoca en las cuentas): cuentas, ecuaciones de 1.º y 2.º
/// grado, regla de tres y sistemas de dos ecuaciones, con los pasos
/// explicados y para escuchar. Se escribe con un teclado matemático o se
/// lee de una foto y se corrige antes de resolver.
class MathScreen extends StatefulWidget {
  const MathScreen({super.key, required this.handler});
  final TtsAudioHandler handler;

  @override
  State<MathScreen> createState() => _MathScreenState();
}

class _MathScreenState extends State<MathScreen> {
  static const _keys = ['x', 'y', '²', '^', '√', '(', ')', '÷', '×', '−', '+', '=', '%', ',', 'nueva línea'];
  static const _examples = ['2x + 3 = 11', 'x² − 5x + 6 = 0', '3/5 = 12/x', '1/2 + 1/3 × 6', 'x + y = 5\nx − y = 1'];

  final _text = TextEditingController();
  final _focus = FocusNode();
  MathSolution? _solution;
  String? _error;
  String? _notice;
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
      try {
        _solution = solveMath(_text.text, method: _method);
        _showSteps = false;
        _error = null;
      } on MathError catch (e) {
        _solution = null;
        _error = e.message;
      }
    });
  }

  Future<void> _photo(ImageSource source) async {
    // La cámara es la propia, con recuadro (como en las apps de matemáticas);
    // de la galería se elige una foto entera.
    final String? path;
    if (source == ImageSource.camera) {
      path = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const MathCameraScreen()));
    } else {
      path = (await ImagePicker().pickImage(source: source, imageQuality: 95))?.path;
    }
    if (path == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final text = await NativeText().recognize(path, languageCorrection: false, minimumTextHeight: 0.01);
      if (!mounted) return;
      final lines = mathLinesIn(text);
      setState(() {
        _solution = null;
        if (text.trim().isEmpty) {
          _error = 'No se encontró texto en la foto. Prueba con más luz o más cerca.';
          _notice = null;
        } else if (lines.isEmpty) {
          _error = 'No encontré un ejercicio de matemáticas en la foto. Encuadra solo la cuenta o la ecuación, o escríbela.';
          _notice = null;
        } else {
          _text.text = lines.join('\n');
          _error = null;
          _notice = lines.length > 2
              ? 'Encontré varios ejercicios: deja solo uno (o dos ecuaciones para un sistema) y toca Resolver.'
              : 'Revisa que el ejercicio se haya leído bien y toca Resolver.';
        }
      });
    } on OcrUnavailable {
      if (mounted) setState(() => _error = 'Este equipo no puede leer texto de fotos.');
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'No se pudo leer la foto.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    if (error != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final solution = _solution;
    return Scaffold(
      appBar: AppBar(title: const Text('Resolver ejercicio')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Cuentas, ecuaciones de 1.º y 2.º grado, regla de tres y sistemas de dos ecuaciones (una por línea).', style: t.bodySmall),
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
                  icon: const Icon(Icons.clear),
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
                    label: k == 'nueva línea' ? const Icon(Icons.keyboard_return, size: 18) : Text(k, style: t.titleMedium),
                    tooltip: k == 'nueva línea' ? 'Otra ecuación (para un sistema)' : null,
                    onPressed: () => _insert(k),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton.icon(onPressed: _busy ? null : _solve, icon: const Icon(Icons.calculate), label: const Text('Resolver')),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Foto del ejercicio',
                onPressed: _busy ? null : () => _photo(ImageSource.camera),
                icon: const Icon(Icons.photo_camera),
              ),
              IconButton.outlined(
                tooltip: 'Desde Fotos',
                onPressed: _busy ? null : () => _photo(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
              ),
            ]),
            if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
            if (_notice != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_notice!, style: t.bodyMedium)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: t.bodyLarge?.copyWith(color: scheme.error)),
              ),
            if (solution == null && _error == null) ...[
              const SizedBox(height: 20),
              Text('Ejemplos', style: t.titleSmall),
              Wrap(spacing: 6, children: [
                for (final e in _examples)
                  ActionChip(label: Text(e.replaceAll('\n', ' ; ')), onPressed: () => setState(() => _text.text = e)),
              ]),
            ],
            if (solution != null) ...[
              const SizedBox(height: 20),
              // Tarjeta de solución, como en las apps de matemáticas: el
              // ejercicio bien escrito, la respuesta grande y los pasos a pedido.
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('PASOS DE LA SOLUCIÓN', style: t.labelSmall),
                    const SizedBox(height: 6),
                    Text(solution.kind, style: t.titleMedium),
                    const SizedBox(height: 12),
                    _Formula(solution.problemLatex, size: 24),
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Icon(Icons.south, size: 20)),
                    Container(
                      padding: const EdgeInsets.only(left: 12),
                      decoration: BoxDecoration(border: Border(left: BorderSide(color: scheme.primary, width: 4))),
                      child: switch (solution.answerLatex) {
                        final tex? => _Formula(tex, size: 30),
                        null => Text(solution.answer, style: t.titleLarge),
                      },
                    ),
                    const SizedBox(height: 16),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton.icon(
                        onPressed: () => setState(() => _showSteps = !_showSteps),
                        icon: Icon(_showSteps ? Icons.expand_less : Icons.arrow_forward),
                        label: Text(_showSteps ? 'Ocultar los pasos' : 'Mostrar los pasos'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () => _listen(solution),
                        icon: Icon(_reading ? Icons.stop : Icons.volume_up),
                        label: Text(_reading ? 'Detener' : 'Escuchar'),
                      ),
                    ]),
                  ]),
                ),
              ),
              if (solution.isSystem) ...[
                const SizedBox(height: 8),
                // Como en clase: el mismo sistema por el método que pida el profesor.
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final m in SystemMethod.values)
                    ChoiceChip(
                      label: Text(m.short),
                      selected: _method == m,
                      onSelected: (_) {
                        _method = m;
                        _solve();
                      },
                    ),
                ]),
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
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('GRÁFICO', style: t.labelSmall),
                      const SizedBox(height: 8),
                      MathGraphView(graph: g),
                    ]),
                  ),
                ),
            ],
          ],
        ),
      ),
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
