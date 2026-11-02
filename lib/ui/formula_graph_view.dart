import 'dart:math' as math;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart';

import '../data/model_store.dart';
import '../domain/math/formula.dart';
import '../domain/math/rational.dart' show MathError;
import '../domain/math/solver.dart' show formulaLinesIn, hasWords;
import '../ocr/ocr_engine.dart' show OcrUnavailable;
import '../platform/formula_model_reader.dart';
import '../platform/native_text.dart';
import '../playback/tts_audio_handler.dart';
import 'exercise_photo.dart';
import 'formula_model_offer.dart';
import 'math_graph_view.dart' show niceGraphStep;
import 'swarm_transition.dart';

/// Graficador: se escriben hasta cuatro fórmulas y se ven juntas. El plano se
/// arrastra y se acerca con dos dedos, y las curvas se pueden escuchar.
class FormulaGraphView extends StatefulWidget {
  const FormulaGraphView({super.key, required this.handler, this.modelStore, this.request});
  final TtsAudioHandler handler;

  /// Para el lector de fórmulas opcional; sin él se usa solo el lector común.
  final ModelStore? modelStore;

  /// Una fórmula que llega de otra parte para graficarla.
  final ValueNotifier<String?>? request;

  @override
  State<FormulaGraphView> createState() => _FormulaGraphViewState();
}

class _Slot {
  _Slot();
  final text = TextEditingController();
  final focus = FocusNode();
  MathFormula? formula;
  String? error;
}

class _FormulaGraphViewState extends State<FormulaGraphView> {
  static const _maxSlots = 4;
  static const _startWidth = 20.0; // de −10 a 10 al abrir
  static const _minUnits = 1e-7, _maxUnits = 1e7; // unidades por píxel
  static const _colors = [Color(0xFFFF9F0A), Color(0xFF64D2FF), Color(0xFF30D158), Color(0xFFFF6482)];
  static const _examples = ['x²', 'sen(x)', '1/x', '2x + 1'];
  static const _keys = ['x', '/', '²', '^', '√(', 'sen(', 'cos(', 'tan(', 'ln(', 'log(', 'abs(', 'π', 'e', '(', ')'];

  final _slots = [_Slot()];
  int _active = 0;
  bool _reading = false;
  bool _busy = false;
  bool _offerModel = false;

  double _centerX = 0, _centerY = 0;
  double? _unitsX, _unitsY; // unidades por píxel; null hasta conocer el tamaño
  Size _size = Size.zero;

  // Al empezar un gesto.
  double _startCenterX = 0, _startCenterY = 0, _startUnitsX = 1, _startUnitsY = 1;
  Offset _startFocal = Offset.zero;

  @override
  void initState() {
    super.initState();
    widget.request?.addListener(_onRequest);
  }

  void _onRequest() {
    final request = widget.request;
    final formula = request?.value;
    if (request == null || formula == null) return;
    request.value = null;
    if (!_slots.any((s) => s.text.text.trim() == formula)) _showRead(formula, [formula]);
  }

  @override
  void dispose() {
    widget.request?.removeListener(_onRequest);
    for (final s in _slots) {
      s.text.dispose();
      s.focus.dispose();
    }
    super.dispose();
  }

  GraphWindow get _window {
    final ux = _unitsX ?? 1, uy = _unitsY ?? 1;
    final halfX = _size.width * ux / 2, halfY = _size.height * uy / 2;
    return (minX: _centerX - halfX, maxX: _centerX + halfX, minY: _centerY - halfY, maxY: _centerY + halfY);
  }

  Iterable<_Slot> get _ready => _slots.where((s) => s.formula != null);

  void _changed(_Slot slot) {
    setState(() {
      final text = slot.text.text;
      if (text.trim().isEmpty) {
        slot.formula = null;
        slot.error = null;
        return;
      }
      try {
        slot.formula = parseFormula(text);
        slot.error = null;
      } on MathError catch (e) {
        slot.formula = null;
        slot.error = e.message;
      }
    });
  }

  void _insert(String value) {
    final slot = _slots[_active];
    final sel = slot.text.selection;
    final text = slot.text.text;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    slot.text.value = TextEditingValue(
      text: text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    _changed(slot);
  }

  void _addSlot() {
    final slot = _Slot();
    setState(() {
      _slots.add(slot);
      _active = _slots.length - 1;
    });
    slot.focus.requestFocus();
  }

  void _removeSlot(int index) {
    final slot = _slots[index];
    setState(() {
      if (_slots.length == 1) {
        slot.text.clear();
        slot.formula = null;
        slot.error = null;
        return;
      }
      _slots.removeAt(index);
      slot.text.dispose();
      slot.focus.dispose();
      _active = _active.clamp(0, _slots.length - 1);
    });
  }

  void _zoom(double factor) {
    setState(() {
      _unitsX = ((_unitsX ?? 1) * factor).clamp(_minUnits, _maxUnits);
      _unitsY = ((_unitsY ?? 1) * factor).clamp(_minUnits, _maxUnits);
    });
  }

  /// Vuelve al inicio: el origen al centro y la misma escala en los dos ejes.
  void _reset() {
    setState(() {
      _centerX = 0;
      _centerY = 0;
      _unitsX = null;
      _unitsY = null;
    });
  }

  /// Ajusta el alto para que las curvas se vean enteras en el ancho actual.
  void _fit() {
    final w = _window;
    final fit = fitHeight(_ready.map((s) => s.formula!.at), w.minX, w.maxX);
    setState(() {
      _centerY = (fit.minY + fit.maxY) / 2;
      _unitsY = ((fit.maxY - fit.minY) / math.max(_size.height, 1)).clamp(_minUnits, _maxUnits);
    });
  }

  /// Lee las fórmulas de una foto y las grafica; si no entiende, deja lo leído
  /// en el cuadro para corregirlo.
  Future<void> _photo(ImageSource source) async {
    final photo = await takeExercisePhoto(context, source);
    if (photo == null || !mounted) return;
    setState(() => _busy = true);
    String? message;
    try {
      final native = NativeText();
      Future<String> read(String path) => native.recognize(path, languageCorrection: false, minimumTextHeight: 0.01);
      var text = await read(photo.path);
      var lines = formulaLinesIn(text);
      final store = widget.modelStore;
      if (store != null && lines.length <= 1 && !hasWords(text)) {
        final plain = await FormulaModelReader(store).read(photo.path);
        if (plain != null) {
          final found = formulaLinesIn(plain);
          if (found.isNotEmpty) lines = found;
        }
      }
      final full = photo.full;
      if (lines.isEmpty && full != null) {
        text = await read(full);
        lines = formulaLinesIn(text);
      }
      if (!mounted) return;
      message = _showRead(text, lines);
      if (lines.isEmpty) setState(() => _offerModel = true);
    } on OcrUnavailable {
      message = 'Este equipo no puede leer texto de fotos.';
    } on PlatformException {
      message = 'No se pudo leer la foto. Prueba con otra más nítida.';
    } finally {
      if (mounted) setState(() => _busy = false);
      await deleteExercisePhoto(photo);
    }
    if (message != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: SwarmText(message)));
    }
  }

  /// Pone lo leído en los cuadros libres. Devuelve el aviso, si hace falta.
  String? _showRead(String text, List<String> lines) {
    if (text.trim().isEmpty) return 'No se encontró texto en la foto. Prueba con más luz o más cerca.';
    final free = _slots.indexWhere((s) => s.text.text.trim().isEmpty);
    if (lines.isEmpty) {
      if (free < 0) return 'No encontré una fórmula en la foto.';
      _slots[free].text.text = text.trim().split('\n').first;
      _changed(_slots[free]);
      return 'No encontré una fórmula. Corrige lo que leí en el cuadro.';
    }
    var placed = 0;
    for (final line in lines) {
      var index = _slots.indexWhere((s) => s.text.text.trim().isEmpty);
      if (index < 0) {
        if (_slots.length >= _maxSlots) break;
        setState(() => _slots.add(_Slot()));
        index = _slots.length - 1;
      }
      _slots[index].text.text = line;
      _changed(_slots[index]);
      placed++;
    }
    return placed < lines.length ? 'Entran $_maxSlots fórmulas: quedaron afuera ${lines.length - placed}.' : null;
  }

  Future<void> _listen() async {
    if (_reading) {
      setState(() => _reading = false);
      await widget.handler.stopAside();
      return;
    }
    final w = _window;
    final said = _ready.map((s) => describeFormula(s.formula!, w.minX, w.maxX)).toList();
    setState(() => _reading = true);
    final error = await widget.handler.speakAside(said);
    if (!mounted) return;
    setState(() => _reading = false);
    if (error != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: SwarmText(error)));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth > c.maxHeight * 1.1;
        if (wide) {
          return Row(
            children: [
              Expanded(child: _plane(context)),
              SizedBox(width: math.min(360, c.maxWidth * 0.45), child: _panel(context)),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: _plane(context)),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: c.maxHeight * 0.45),
              child: _panel(context),
            ),
          ],
        );
      },
    );
  }

  Widget _plane(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 12);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: LayoutBuilder(
          builder: (context, c) {
            _size = c.biggest;
            final units = _startWidth / math.max(c.maxWidth, 1);
            _unitsX ??= units;
            _unitsY ??= units;
            final curves = [
              for (final (i, s) in _slots.indexed)
                if (s.formula case final f?) (formula: f, color: _colors[i % _colors.length]),
            ];
            return Stack(
              children: [
                Positioned.fill(
                  child: Semantics(
                    image: true,
                    label: curves.isEmpty ? 'Plano vacío' : 'Gráfico de ${curves.length} fórmulas. Usa Escuchar.',
                    child: GestureDetector(
                      onScaleStart: (d) {
                        _startCenterX = _centerX;
                        _startCenterY = _centerY;
                        _startUnitsX = _unitsX!;
                        _startUnitsY = _unitsY!;
                        _startFocal = d.localFocalPoint;
                      },
                      onScaleUpdate: (d) => setState(() {
                        // El punto que estaba bajo los dedos sigue bajo los dedos.
                        final ux = (_startUnitsX / d.scale).clamp(_minUnits, _maxUnits);
                        final uy = (_startUnitsY / d.scale).clamp(_minUnits, _maxUnits);
                        final middle = _size.center(Offset.zero);
                        final from = _startFocal - middle, to = d.localFocalPoint - middle;
                        _unitsX = ux;
                        _unitsY = uy;
                        _centerX = _startCenterX + from.dx * _startUnitsX - to.dx * ux;
                        _centerY = _startCenterY - from.dy * _startUnitsY + to.dy * uy;
                      }),
                      child: CustomPaint(
                        painter: _PlanePainter(
                          window: _window,
                          curves: curves,
                          background: scheme.surfaceContainerLow,
                          axis: scheme.onSurface.withValues(alpha: 0.6),
                          grid: scheme.onSurface.withValues(alpha: 0.08),
                          dot: scheme.onSurface,
                          label: label,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Column(
                    children: [
                      _planeButton(CupertinoIcons.plus, 'Acercar', () => _zoom(1 / 1.5)),
                      _planeButton(CupertinoIcons.minus, 'Alejar', () => _zoom(1.5)),
                      _planeButton(
                        CupertinoIcons.arrow_up_down,
                        'Ajustar el alto a las curvas',
                        curves.isEmpty ? null : _fit,
                      ),
                      _planeButton(CupertinoIcons.scope, 'Volver al inicio', _reset),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _planeButton(IconData icon, String tooltip, VoidCallback? onTap) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: IconButton.filledTonal(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onTap,
      icon: Icon(icon, size: 18),
    ),
  );

  Widget _panel(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final empty = _ready.isEmpty && _slots.every((s) => s.text.text.isEmpty);
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      children: [
        if (_busy) const Padding(padding: EdgeInsets.only(bottom: 8), child: LinearProgressIndicator()),
        if (_offerModel && widget.modelStore != null) FormulaModelOffer(store: widget.modelStore!),
        for (final (i, s) in _slots.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextField(
              controller: s.text,
              focusNode: s.focus,
              style: t.titleMedium,
              keyboardType: TextInputType.visiblePassword, // sin autocorregir «sen»
              autocorrect: false,
              enableSuggestions: false,
              onTap: () => _active = i,
              onChanged: (_) => _changed(s),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'y = x²',
                errorText: s.error,
                errorMaxLines: 2,
                prefixIcon: Icon(Icons.circle, size: 14, color: _colors[i % _colors.length]),
                suffixIcon: IconButton(
                  tooltip: 'Borrar fórmula',
                  icon: const Icon(CupertinoIcons.xmark_circle, size: 20),
                  onPressed: () => _removeSlot(i),
                ),
              ),
            ),
          ),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              IconButton.outlined(
                tooltip: 'Foto de la fórmula',
                visualDensity: VisualDensity.compact,
                onPressed: _busy ? null : () => _photo(ImageSource.camera),
                icon: const Icon(CupertinoIcons.camera, size: 18),
              ),
              IconButton.outlined(
                tooltip: 'Desde Fotos',
                visualDensity: VisualDensity.compact,
                onPressed: _busy ? null : () => _photo(ImageSource.gallery),
                icon: const Icon(CupertinoIcons.photo_on_rectangle, size: 18),
              ),
              const SizedBox(width: 6),
              for (final k in _keys)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    label: Text(k.endsWith('(') && k.length > 1 ? k.substring(0, k.length - 1) : k),
                    onPressed: () => _insert(k),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (empty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in _examples)
                ActionChip(
                  label: Text('y = $e'),
                  onPressed: () {
                    _slots[_active].text.text = e;
                    _changed(_slots[_active]);
                  },
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Las funciones van en radianes. Arrastra el plano y acércalo con dos dedos.',
            style: t.bodySmall?.copyWith(color: scheme.onSurface.withValues(alpha: 0.7)),
          ),
        ] else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _ready.isEmpty ? null : _listen,
                icon: Icon(_reading ? CupertinoIcons.stop_fill : CupertinoIcons.speaker_2),
                label: Text(_reading ? 'Detener' : 'Escuchar'),
              ),
              if (_slots.length < _maxSlots)
                OutlinedButton.icon(
                  onPressed: _addSlot,
                  icon: const Icon(CupertinoIcons.plus),
                  label: const Text('Otra fórmula'),
                ),
            ],
          ),
      ],
    );
  }
}

class _PlanePainter extends CustomPainter {
  _PlanePainter({
    required this.window,
    required this.curves,
    required this.background,
    required this.axis,
    required this.grid,
    required this.dot,
    required this.label,
  });

  final GraphWindow window;
  final List<({MathFormula formula, Color color})> curves;
  final Color background, axis, grid, dot;
  final TextStyle label;

  /// Con más puntos que esto, marcarlos todos sería puro ruido (y = sen(50x)).
  static const _maxMarks = 12;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final w = window;
    if (w.maxX <= w.minX || w.maxY <= w.minY) return;
    Offset at(double x, double y) => Offset(
      (x - w.minX) / (w.maxX - w.minX) * size.width,
      size.height - (y - w.minY) / (w.maxY - w.minY) * size.height,
    );

    final gridPaint = Paint()..color = grid;
    // Un cuadro de unos 80 píxeles (niceGraphStep reparte en 8) en los dos ejes.
    final stepX = niceGraphStep((w.maxX - w.minX) * 640 / math.max(size.width, 1));
    final stepY = niceGraphStep((w.maxY - w.minY) * 640 / math.max(size.height, 1));
    final xStart = (w.minX / stepX).ceil(), xEnd = (w.maxX / stepX).floor();
    final yStart = (w.minY / stepY).ceil(), yEnd = (w.maxY / stepY).floor();
    for (var k = xStart; k <= xEnd; k++) {
      canvas.drawLine(at(k * stepX, w.minY), at(k * stepX, w.maxY), gridPaint);
    }
    for (var k = yStart; k <= yEnd; k++) {
      canvas.drawLine(at(w.minX, k * stepY), at(w.maxX, k * stepY), gridPaint);
    }
    final axisPaint = Paint()
      ..color = axis
      ..strokeWidth = 1.2;
    canvas.drawLine(at(w.minX, 0), at(w.maxX, 0), axisPaint);
    canvas.drawLine(at(0, w.minY), at(0, w.maxY), axisPaint);

    // Los números siguen pegados al borde si el eje quedó fuera de la vista.
    final numberY = at(0, 0).dy.clamp(2.0, size.height - 18);
    final numberX = at(0, 0).dx.clamp(2.0, size.width - 40);
    for (var k = xStart; k <= xEnd; k++) {
      if (k == 0) continue;
      _text(canvas, formatNumber(k * stepX), Offset(at(k * stepX, 0).dx + 2, numberY + 2));
    }
    for (var k = yStart; k <= yEnd; k++) {
      if (k == 0) continue;
      _text(canvas, formatNumber(k * stepY), Offset(numberX + 3, at(0, k * stepY).dy - 8));
    }

    for (final c in curves) {
      final paint = Paint()
        ..color = c.color
        ..strokeWidth = 2.6
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;
      for (final segment in plotSegments(c.formula.at, w)) {
        final path = Path();
        for (final (i, p) in segment.indexed) {
          final o = at(p.$1, p.$2);
          if (i == 0) {
            path.moveTo(o.dx, o.dy);
          } else {
            path.lineTo(o.dx, o.dy);
          }
        }
        canvas.drawPath(path, paint);
      }
    }

    // Dónde cortan los ejes: se marca, con su valor si caben.
    final marks = <(double, double)>[
      for (final c in curves) ...[
        for (final r in formulaRoots(c.formula.at, w.minX, w.maxX)) (r, 0.0),
        if (c.formula.at(0) case final y when y.isFinite && y >= w.minY && y <= w.maxY && w.minX <= 0 && w.maxX >= 0)
          (0.0, y),
      ],
    ];
    if (marks.length <= _maxMarks) {
      final paint = Paint()..color = dot;
      for (final (x, y) in marks) {
        canvas.drawCircle(at(x, y), 4, paint);
      }
    }
  }

  void _text(Canvas canvas, String s, Offset o) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: label.copyWith(fontSize: 10, color: axis),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, o);
    tp.dispose();
  }

  @override
  bool shouldRepaint(_PlanePainter old) => true;
}
