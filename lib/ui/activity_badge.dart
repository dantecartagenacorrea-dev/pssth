import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/activity.dart';

/// Arriba al centro, mientras la app trabaja en segundo plano: un punto
/// naranja que late. Al empezar cada trabajo dice cuál es durante unos
/// segundos y vuelve a ser solo el punto, así no tapa los botones de arriba.
/// No se toca; el lector de pantalla lo anuncia.
class ActivityBadge extends StatefulWidget {
  const ActivityBadge({super.key});

  @override
  State<ActivityBadge> createState() => _ActivityBadgeState();
}

class _ActivityBadgeState extends State<ActivityBadge> with SingleTickerProviderStateMixin {
  static const _orange = Color(0xFFD97757);
  static const _labelFor = Duration(seconds: 3);
  late final _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  List<String> _work = const [];
  bool _showLabel = false;
  Timer? _hideLabel;

  @override
  void initState() {
    super.initState();
    Activity.current.addListener(_changed);
    _changed();
  }

  @override
  void dispose() {
    Activity.current.removeListener(_changed);
    _hideLabel?.cancel();
    _spin.dispose();
    super.dispose();
  }

  void _changed() {
    final work = Activity.current.value;
    final started = work.isNotEmpty && (_work.isEmpty || work.first != _work.first);
    _work = work;
    if (started) {
      _showLabel = true;
      _hideLabel?.cancel();
      _hideLabel = Timer(_labelFor, () {
        if (mounted) setState(() => _showLabel = false);
      });
    }
    // El giro solo corre mientras hay algo (no gasta batería).
    if (work.isNotEmpty && !_spin.isAnimating) _spin.repeat();
    if (work.isEmpty) _spin.stop();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.of(context).disableAnimations;
    final busy = _work.isNotEmpty;
    final label = !busy ? '' : '${_work.first}…${_work.length > 1 ? ' +${_work.length - 1}' : ''}';
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          // Encima de todas las pantallas no hay estilo de texto: el propio.
          child: Material(
            type: MaterialType.transparency,
            child: AnimatedOpacity(
              opacity: busy ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: Semantics(
                liveRegion: true,
                label: busy ? label : null,
                excludeSemantics: true,
                child: Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: EdgeInsets.symmetric(horizontal: _showLabel ? 10 : 5, vertical: 5),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _orange.withValues(alpha: 0.35)),
                  ),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Tres puntos que giran en 3D sobre un eje (quietos si el
                        // sistema pide reducir el movimiento).
                        SizedBox(
                          width: 18,
                          height: 8,
                          child: CustomPaint(painter: _Orbit(still ? const AlwaysStoppedAnimation(0.08) : _spin)),
                        ),
                        if (_showLabel && busy) ...[
                          const SizedBox(width: 6),
                          Text(
                            label,
                            textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
                            style: const TextStyle(color: _orange, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tres puntos sobre un aro que gira alrededor de un eje vertical: el de
/// adelante se ve más grande y fuerte; los de atrás, chicos y tenues.
class _Orbit extends CustomPainter {
  _Orbit(this.turn) : super(repaint: turn);
  final Animation<double> turn;

  static const _orange = Color(0xFFD97757);

  @override
  void paint(Canvas canvas, Size size) {
    final dots = <(double depth, Offset at)>[];
    for (var k = 0; k < 3; k++) {
      final a = (turn.value + k / 3) * 2 * math.pi;
      final x = size.width / 2 + math.sin(a) * (size.width / 2 - 3);
      dots.add((math.cos(a), Offset(x, size.height / 2)));
    }
    // Los de atrás primero, para que el de adelante quede encima.
    dots.sort((p, q) => p.$1.compareTo(q.$1));
    for (final (depth, at) in dots) {
      final near = (depth + 1) / 2; // 0 atrás, 1 adelante
      canvas.drawCircle(at, 1.6 + 1.9 * near, Paint()..color = _orange.withValues(alpha: 0.3 + 0.7 * near));
    }
  }

  @override
  bool shouldRepaint(_Orbit old) => old.turn != turn;
}
