import 'package:flutter/material.dart';

import '../data/model_store.dart';
import '../playback/tts_audio_handler.dart';
import 'calculator_view.dart';
import 'formula_graph_view.dart';
import 'math_screen.dart';
import 'premium.dart';

/// La pestaña Calculadora: resolver ejercicios con pasos, hacer cuentas y
/// graficar fórmulas. Cada parte conserva lo suyo al pasar a otra.
class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key, required this.handler, this.modelStore});
  final TtsAudioHandler handler;
  final ModelStore? modelStore;

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

class _CalculatorScreenState extends State<CalculatorScreen> {
  static const _parts = ['Resolver', 'Calcular', 'Graficar'];
  int _part = 1;
  final _graphRequest = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _graphRequest.dispose();
    super.dispose();
  }

  void _open(int part) {
    if (part == _part) return;
    FocusManager.instance.primaryFocus?.unfocus();
    // Lo que se estaba leyendo en voz alta es de la otra parte.
    widget.handler.stopAside();
    setState(() => _part = part);
  }

  @override
  Widget build(BuildContext context) {
    return PremiumPage(
      title: 'Calculadora',
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Wrap(
                spacing: 8,
                children: [
                  for (final (i, name) in _parts.indexed)
                    ChoiceChip(label: Text(name), selected: _part == i, onSelected: (_) => _open(i)),
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _part,
                sizing: StackFit.expand,
                children: [
                  MathSolveView(
                    handler: widget.handler,
                    modelStore: widget.modelStore,
                    onGraph: (formula) {
                      _graphRequest.value = formula;
                      _open(2);
                    },
                  ),
                  const CalculatorView(),
                  FormulaGraphView(handler: widget.handler, modelStore: widget.modelStore, request: _graphRequest),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
