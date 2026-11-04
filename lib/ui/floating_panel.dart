import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'premium.dart';

/// Panel desde abajo, flotante y bien definido.
Future<T?> showFloatingSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: isScrollControlled,
  backgroundColor: Colors.transparent,
  elevation: 0,
  builder: (c) => FloatingPanel(child: builder(c)),
);

/// Panel flotante y bien definido: separado de los bordes, esquinas
/// redondeadas, borde fino y ancho de hoja en tablet.
class FloatingPanel extends StatelessWidget {
  const FloatingPanel({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(Premium.radiusSheet),
              boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 8))],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Premium.radiusSheet),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SheetHandle(),
                  Flexible(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
