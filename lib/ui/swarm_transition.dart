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

/// Diálogo cuyo contenido se forma de la dispersión al abrirse y se deshace
/// al cerrarse (como las pantallas).
Future<T?> showSwarmDialog<T>({required BuildContext context, required WidgetBuilder builder, bool barrierDismissible = true}) =>
    showDialog<T>(context: context, barrierDismissible: barrierDismissible, builder: (c) => SwarmPopup(child: builder(c)));

/// Panel desde abajo cuyo contenido se forma de la dispersión al abrirse y se
/// deshace al cerrarse.
Future<T?> showSwarmSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool showDragHandle = false,
}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      builder: (c) => SwarmPopup(child: builder(c)),
    );

/// Envoltorio para el contenido de un diálogo o panel: usa las animaciones de
/// su ruta para formarse con el enjambre y deshacerse al cerrarse, sin tocar
/// la pantalla de atrás (ni el río de letras).
class SwarmPopup extends StatelessWidget {
  const SwarmPopup({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final route = ModalRoute.of(context);
    if (route?.animation == null || MediaQuery.disableAnimationsOf(context)) return child;
    return _SwarmPage(
      animation: route!.animation!,
      secondaryAnimation: kAlwaysDismissedAnimation,
      sphere: false,
      overlay: true,
      child: child,
    );
  }
}

class _SwarmPage extends StatefulWidget {
  const _SwarmPage({
    required this.animation,
    required this.secondaryAnimation,
    required this.sphere,
    this.overlay = false,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final bool sphere;

  /// Encima de otra pantalla (diálogo o panel): espera a que termine de
  /// abrirse y no toca las letras de atrás.
  final bool overlay;
  final Widget child;

  @override
  State<_SwarmPage> createState() => _SwarmPageState();
}

class _SwarmPageState extends State<_SwarmPage> {
  /// Vuelo mínimo (para que se vea el viaje) y máximo (si alguna letra se
  /// demora, la pantalla aparece igual) antes de mostrar la pantalla.
  static const _minFlight = Duration(milliseconds: 550);
  static const _maxFlight = Duration(milliseconds: 1700);
  static const _poll = Duration(milliseconds: 40);
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
  /// cuando sus letras llegaron a su lugar.
  void _enter() {
    final my = ++_gen;
    if (_shown) setState(() => _shown = false);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Sin el enjambre listo (recién abierta la app) la pantalla aparecería
      // ya formada: se espera a que pueda armarse desde la dispersión.
      await Swarm.instance.ready.timeout(const Duration(seconds: 3), onTimeout: () {});
      // Un panel sube deslizándose: sus letras se ubican cuando quedó quieto.
      while (widget.overlay && widget.animation.status == AnimationStatus.forward) {
        await Future.delayed(_poll);
        if (!mounted || my != _gen) return;
      }
      final ctx = _contentKey.currentContext;
      if (!mounted || my != _gen || ctx == null || !ctx.mounted) return;
      final glyphs = collectGlyphs(ctx);
      await Swarm.instance.ensure(glyphs); // los íconos nuevos, al atlas
      if (!mounted || my != _gen) return;
      Swarm.instance.formText(glyphs, sphere: widget.sphere, overlay: widget.overlay);
      final started = DateTime.now();
      while (true) {
        await Future.delayed(_poll);
        if (!mounted || my != _gen) return;
        final waited = DateTime.now().difference(started);
        if (waited >= _maxFlight || (waited >= _minFlight && Swarm.instance.textArrived())) break;
      }
      setState(() => _shown = true);
      Swarm.instance.settleText();
    });
  }

  /// La pantalla se deshace en sus propias letras (las que se ven ahora) y
  /// se apaga.
  void _leave() {
    _gen++;
    final ctx = _contentKey.currentContext;
    final glyphs = ctx != null && _shown ? collectGlyphs(ctx) : const <SwarmGlyph>[];
    if (widget.overlay) {
      Swarm.instance.dissolveOverlay(glyphs); // la pantalla de atrás sigue igual
    } else {
      Swarm.instance.liftText(glyphs);
    }
    if (_shown) setState(() => _shown = false);
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        key: _contentKey,
        opacity: _shown ? 1 : 0,
        // Al aparecer, el texto real y las letras del enjambre se cruzan; al
        // irse, las letras toman su lugar en el mismo cuadro.
        duration: Duration(milliseconds: _shown ? 220 : 60),
        child: widget.child,
      );
}
