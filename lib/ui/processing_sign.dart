import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Signo discreto de "estoy trabajando": tres puntos que respiran en ola, sin
/// porcentajes. Se ve solo mientras [active].
class ProcessingSign extends StatefulWidget {
  const ProcessingSign({super.key, required this.active, this.tooltip, this.onTap});
  final bool active;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  State<ProcessingSign> createState() => _ProcessingSignState();
}

class _ProcessingSignState extends State<ProcessingSign> with SingleTickerProviderStateMixin {
  late final _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    if (widget.active) _wave.repeat();
  }

  @override
  void didUpdateWidget(ProcessingSign old) {
    super.didUpdateWidget(old);
    if (widget.active && !_wave.isAnimating) _wave.repeat();
    if (!widget.active && _wave.isAnimating) _wave.stop();
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sign = AnimatedBuilder(
      animation: _wave,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Opacity(
                opacity: 0.25 + 0.75 * (0.5 + 0.5 * math.sin((_wave.value - i / 6) * 2 * math.pi)),
                child: SizedBox.square(
                  dimension: 5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: !widget.active
          ? const SizedBox.shrink()
          : Tooltip(
              message: widget.tooltip ?? '',
              child: InkResponse(
                onTap: widget.onTap,
                radius: 22,
                child: Padding(padding: const EdgeInsets.all(12), child: sign),
              ),
            ),
    );
  }
}
