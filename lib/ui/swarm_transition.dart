import 'package:flutter/material.dart';

import 'dot_field.dart';
import 'swarm.dart';

/// Transición entre pantallas con el enjambre de letras: la pantalla que se va
/// suelta sus letras al enjambre, que vuela a formar los textos de la nueva; la
/// nueva aparece cuando sus letras llegan. Al volver pasa lo mismo al revés.
class SwarmTransitionsBuilder extends PageTransitionsBuilder {
  const SwarmTransitionsBuilder();

  /// Ruta de la pantalla principal: ahí el enjambre sobrante forma la esfera.
  static const home = 'inicio';

  /// Ruta con fondo propio y opaco (el reproductor): sin fondo de puntos, que
  /// quedaría tapado y gastaría cuadros.
  static const solidBackground = 'fondo-propio';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 700);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final page = route.settings.name == solidBackground
        ? child
        : Stack(fit: StackFit.expand, children: [const DotField(), child]);
    // La entrada (primera ruta) tiene su propia animación.
    if (route.settings.name == Navigator.defaultRouteName) return page;
    if (MediaQuery.disableAnimationsOf(context)) return FadeTransition(opacity: animation, child: page);
    return _SwarmPage(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      sphere: route.settings.name == home,
      child: page,
    );
  }
}

class _SwarmPage extends StatefulWidget {
  const _SwarmPage({
    required this.animation,
    required this.secondaryAnimation,
    required this.sphere,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final bool sphere;
  final Widget child;

  @override
  State<_SwarmPage> createState() => _SwarmPageState();
}

class _SwarmPageState extends State<_SwarmPage> {
  /// Cuánto esperar a que las letras lleguen antes de mostrar la pantalla.
  static const _flight = Duration(milliseconds: 650);
  final _contentKey = GlobalKey();
  bool _shown = false;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_onRoute);
    widget.secondaryAnimation.addStatusListener(_onCovered);
    _enter();
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onRoute);
    widget.secondaryAnimation.removeStatusListener(_onCovered);
    super.dispose();
  }

  void _onRoute(AnimationStatus s) {
    if (s == AnimationStatus.reverse) _leave(); // se cierra esta pantalla
  }

  void _onCovered(AnimationStatus s) {
    if (s == AnimationStatus.forward) _leave(); // otra se abre encima
    if (s == AnimationStatus.reverse) _enter(); // se vuelve a esta
  }

  /// Llama al enjambre a formar los textos de esta pantalla y la muestra
  /// cuando llegan.
  void _enter() {
    final my = ++_gen;
    if (_shown) setState(() => _shown = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _contentKey.currentContext;
      if (!mounted || my != _gen || ctx == null) return;
      Swarm.instance.formText(collectGlyphs(ctx), sphere: widget.sphere);
      Future.delayed(_flight, () {
        if (!mounted || my != _gen) return;
        setState(() => _shown = true);
        Swarm.instance.settleText();
      });
    });
  }

  /// Sus letras vuelven al enjambre y la pantalla se apaga.
  void _leave() {
    _gen++;
    Swarm.instance.liftText();
    if (_shown) setState(() => _shown = false);
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        key: _contentKey,
        opacity: _shown ? 1 : 0,
        duration: Duration(milliseconds: _shown ? 300 : 120),
        child: widget.child,
      );
}
