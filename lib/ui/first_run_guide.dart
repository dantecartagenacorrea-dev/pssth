import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'swarm_transition.dart';

/// Guía corta de la primera vez (3 pasos): qué se puede abrir, cómo se
/// escucha y cómo se estudia. Solo a quien empieza con la biblioteca vacía.
class FirstRunGuide {
  FirstRunGuide._();
  static const _seenKey = 'guide_seen';

  static const _steps = [
    (
      icon: CupertinoIcons.folder,
      title: 'Abre lo que quieras escuchar',
      text: 'Un PDF, un EPUB, una foto, una hoja escaneada o un enlace. Todo se queda en tu equipo.',
    ),
    (
      icon: CupertinoIcons.play_circle,
      title: 'Escucha y sigue la lectura',
      text:
          'La palabra que suena se marca en el texto. Cambia la velocidad, la voz y el tamaño de la letra cuando '
          'quieras.',
    ),
    (
      icon: CupertinoIcons.question_circle,
      title: 'Estudia sin salir del texto',
      text: 'Resumen con los conceptos clave y preguntas para repasar, al instante y sin Internet.',
    ),
  ];

  /// La muestra si nunca se vio y [isNewUser]. Devuelve cuando se cierra.
  static Future<void> showOnce(BuildContext context, {required bool isNewUser}) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seenKey) ?? false) return;
    await prefs.setBool(_seenKey, true);
    if (!isNewUser || !context.mounted) return;
    await showSwarmDialog<void>(context: context, builder: (_) => const _GuideDialog());
  }
}

class _GuideDialog extends StatefulWidget {
  const _GuideDialog();

  @override
  State<_GuideDialog> createState() => _GuideDialogState();
}

class _GuideDialogState extends State<_GuideDialog> {
  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final step = FirstRunGuide._steps[_step];
    final last = _step == FirstRunGuide._steps.length - 1;
    final t = Theme.of(context).textTheme;
    return AlertDialog(
      icon: Icon(step.icon, size: 40),
      title: Text(step.title, textAlign: TextAlign.center),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(step.text, textAlign: TextAlign.center, style: t.bodyLarge),
          const SizedBox(height: 16),
          Text('${_step + 1} de ${FirstRunGuide._steps.length}', style: t.bodySmall),
        ],
      ),
      actions: [
        if (!last) TextButton(onPressed: () => Navigator.pop(context), child: const Text('Saltar')),
        FilledButton(
          onPressed: last ? () => Navigator.pop(context) : () => setState(() => _step++),
          child: Text(last ? 'Empezar' : 'Siguiente'),
        ),
      ],
    );
  }
}
