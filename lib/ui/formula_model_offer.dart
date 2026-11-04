import 'dart:io';

import 'package:flutter/material.dart';

import '../data/model_store.dart';

/// Ofrece bajar el lector de fórmulas mientras no esté instalado: es opcional y
/// solo lo baja quien lo pide. Instalado, no se muestra.
class FormulaModelOffer extends StatefulWidget {
  const FormulaModelOffer({super.key, required this.store});
  final ModelStore store;

  @override
  State<FormulaModelOffer> createState() => _FormulaModelOfferState();
}

class _FormulaModelOfferState extends State<FormulaModelOffer> {
  Future<void> _install() async {
    try {
      await widget.store.install(formulaModel);
    } on ModelInstallException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        if (!Platform.isAndroid || widget.store.isInstalled(formulaModel)) return const SizedBox.shrink();
        final progress = widget.store.progressOf(formulaModel);
        final installing = widget.store.isInstalling(formulaModel);
        final megabytes = (formulaModel.sizeBytes / 1000000).round();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Lector de fórmulas', style: t.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Lee mejor las fracciones y las fotos difíciles, sin internet. '
                  'Se baja una sola vez ($megabytes MB).',
                  style: t.bodySmall,
                ),
                const SizedBox(height: 10),
                if (installing) ...[
                  LinearProgressIndicator(value: progress?.fraction),
                  const SizedBox(height: 6),
                  Text(progress?.label ?? 'Descargando…', style: t.bodySmall),
                ] else
                  FilledButton.tonal(onPressed: _install, child: const Text('Bajar el lector')),
              ],
            ),
          ),
        );
      },
    );
  }
}
