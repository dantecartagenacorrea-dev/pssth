import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/retype_ink.dart';
import '../domain/retype_text.dart';
import '../domain/scanned_pdf.dart';

/// «Como nuevo»: cada renglón de la foto con lo que se leyó justo debajo, para
/// compararlos y corregir antes de armar la hoja nueva.
class RetypeEditor extends StatelessWidget {
  const RetypeEditor({
    super.key,
    required this.photo,
    required this.width,
    required this.height,
    required this.lines,
    required this.controllers,
    this.doubts = const {},
    this.readByAi = false,
    this.marks = const [],
    this.hiddenMarks = const {},
    this.onToggleMark,
  });

  final ImageProvider photo;
  final int width;
  final int height;
  final List<ScannedLine> lines;
  final List<TextEditingController> controllers;

  /// Renglones en que los dos lectores no coinciden.
  final Set<int> doubts;
  final bool readByAi;

  /// Firmas y sellos que pasan a la hoja nueva, y los que se pidió sacar.
  final List<PageMark> marks;
  final Set<int> hiddenMarks;
  final ValueChanged<int>? onToggleMark;

  /// Lo que pasa como imagen: tocándolo se saca o se vuelve a poner.
  Widget _marksStrip(ThemeData theme) {
    if (marks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Firmas y sellos que pasan a la hoja nueva. Toca uno para sacarlo.', style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (i, mark) in marks.indexed)
                Semantics(
                  button: true,
                  selected: !hiddenMarks.contains(i),
                  label: 'Firma o sello ${i + 1}',
                  child: GestureDetector(
                    onTap: onToggleMark == null ? null : () => onToggleMark!(i),
                    child: Opacity(
                      opacity: hiddenMarks.contains(i) ? 0.3 : 1,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        color: Colors.white,
                        child: Image.memory(mark.jpeg, height: 64, excludeFromSemantics: true),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  bool _isDoubtful(int index) => doubts.contains(index) || looksMisread(controllers[index].text);

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('En esta página no se leyó texto: irá con su foto.', textAlign: TextAlign.center),
        ),
      );
    }
    final theme = Theme.of(context);
    final doubtful = [
      for (var i = 0; i < controllers.length; i++)
        if (_isDoubtful(i)) i,
    ].length;
    return ListView.builder(
      itemCount: lines.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'La calidad depende de la foto: mientras más nítida, legible y entendible, mejor saldrá. '
              '${doubtful == 0 ? '' : 'Hay $doubtful ${doubtful == 1 ? 'renglón dudoso' : 'renglones dudosos'}, en naranja. '}'
              '${readByAi ? 'Leído con la IA de tu computadora, que también puede equivocarse. ' : ''}'
              'Compara cada renglón con la foto, sobre todo nombres y números. '
              'Saldrá como recién impreso, con las mismas palabras. Es una transcripción: '
              'la copia con la foto queda al lado.',
              style: theme.textTheme.bodySmall,
            ),
          );
        }
        if (i == 1) return _marksStrip(theme);
        final index = i - 2;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _LineCrop(photo: photo, width: width, height: height, line: lines[index]),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controllers[index],
                builder: (context, value, _) => TextField(
                  controller: controllers[index],
                  maxLines: null,
                  // Del tamaño de la foto de arriba: así se comparan de un vistazo.
                  style: theme.textTheme.bodyMedium,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    filled: _isDoubtful(index) ? true : null,
                    fillColor: _isDoubtful(index) ? const Color(0x55FF9F0A) : null,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// El pedazo de la foto donde está el renglón.
class _LineCrop extends StatelessWidget {
  const _LineCrop({required this.photo, required this.width, required this.height, required this.line});

  final ImageProvider photo;
  final int width;
  final int height;
  final ScannedLine line;

  static const _maxHeight = 44.0;

  @override
  Widget build(BuildContext context) {
    // Un poco de aire alrededor: una letra alta o una tilde no quedan cortadas.
    final air = line.height * 0.3;
    final top = math.max(0.0, line.top - air);
    final tall = math.min(1 - top, line.height + 2 * air);
    final cropWidth = math.max(line.width, 1e-3);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.min(constraints.maxWidth / (cropWidth * width), _maxHeight / (tall * height));
        return ExcludeSemantics(
          child: ClipRect(
            child: SizedBox(
              height: tall * height * scale,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned(
                    left: -line.left * width * scale,
                    top: -top * height * scale,
                    width: width * scale,
                    height: height * scale,
                    child: Image(image: photo, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
