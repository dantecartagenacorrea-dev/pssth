import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'dot_field.dart';
import 'premium.dart';
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
    // El fondo de puntos es uno solo, detrás de todas las pantallas (en la
    // app): durante una transición no se dibujan dos.
    final page = route.settings.name == solidBackground ? DotFieldPause(child: child) : child;
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
Future<T?> showSwarmDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showDialog<T>(
  context: context,
  barrierDismissible: barrierDismissible,
  builder: (c) => SwarmPopup(child: builder(c)),
);

/// Panel desde abajo cuyo contenido se forma de la dispersión al abrirse y se
/// deshace al cerrarse.
Future<T?> showSwarmSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool showDragHandle = false,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: isScrollControlled,
  backgroundColor: Colors.transparent,
  elevation: 0,
  builder: (c) => FloatingPanel(child: SwarmPopup(child: builder(c))),
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
              child: Column(mainAxisSize: MainAxisSize.min, children: [const SheetHandle(), Flexible(child: child)]),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Botón de menú (⋯) cuyas opciones se forman de la dispersión: en vez de la
/// lista desplegable abre un panel del enjambre. Mismas opciones que un
/// PopupMenuButton (sus PopupMenuItem).
class SwarmMenuButton<T> extends StatelessWidget {
  const SwarmMenuButton({super.key, this.tooltip, this.icon, required this.onSelected, required this.itemBuilder});
  final String? tooltip;
  final Widget? icon;
  final ValueChanged<T> onSelected;
  final List<PopupMenuEntry<T>> Function(BuildContext context) itemBuilder;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    icon: icon ?? Icon(CupertinoIcons.ellipsis),
    onPressed: () async {
      final items = itemBuilder(context).whereType<PopupMenuItem<T>>().toList();
      final value = await showSwarmSheet<T>(
        context: context,
        builder: (c) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final item in items) ListTile(title: item.child, onTap: () => Navigator.pop(c, item.value)),
            ],
          ),
        ),
      );
      if (value != null && context.mounted) onSelected(value);
    },
  );
}

/// Texto de un aviso de abajo: espera a que el aviso suba, se forma con el
/// enjambre y, al irse el aviso, sus letras se sueltan y se apagan.
class SwarmText extends StatelessWidget {
  const SwarmText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => SwarmArrival(
    delay: const Duration(milliseconds: 320), // el aviso termina de subir
    dissolve: true,
    child: Text(text),
  );
}

/// Contenido que llega después de abierta la pantalla (un resumen, la
/// pregunta siguiente): se forma con el enjambre al aparecer, sin tocar lo que
/// ya estaba. Si la pantalla todavía se está formando, aparece con ella. Para
/// que vuelva a formarse cuando cambia, darle otra [Key].
class SwarmArrival extends StatefulWidget {
  const SwarmArrival({super.key, this.delay = Duration.zero, this.dissolve = false, required this.child});
  final Duration delay;

  /// Al quitarse, sus letras se sueltan y se apagan (un aviso que se va). Sin
  /// esto, se van con su pantalla.
  final bool dissolve;
  final Widget child;

  @override
  State<SwarmArrival> createState() => _SwarmArrivalState();
}

class _SwarmArrivalState extends State<SwarmArrival> {
  final _key = GlobalKey();
  List<SwarmGlyph> _glyphs = const [];
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    // Dentro de una pantalla que todavía se forma, sus letras ya van en ella.
    final page = context.findAncestorStateOfType<_SwarmPageState>();
    if (page != null && !page._shown) {
      _shown = true;
      return;
    }
    _form();
  }

  Future<void> _form() async {
    await Future.delayed(widget.delay);
    await WidgetsBinding.instance.endOfFrame; // ya tiene tamaño y lugar
    final ctx = _key.currentContext;
    if (!mounted || ctx == null || !ctx.mounted || MediaQuery.disableAnimationsOf(ctx)) {
      if (mounted) setState(() => _shown = true);
      return;
    }
    _glyphs = collectGlyphs(ctx);
    if (_glyphs.isEmpty) {
      setState(() => _shown = true);
      return;
    }
    await Swarm.instance.ensure(_glyphs); // los íconos nuevos, al atlas
    if (!mounted) return;
    Swarm.instance.formText(_glyphs, sphere: false, overlay: true);
    final started = DateTime.now();
    while (mounted && DateTime.now().difference(started) < _SwarmPageState._maxFlight) {
      await Future.delayed(const Duration(milliseconds: 40));
      if (Swarm.instance.textArrived()) break;
    }
    if (!mounted) return;
    setState(() => _shown = true);
    Swarm.instance.settleText();
  }

  @override
  void dispose() {
    if (_shown && widget.dissolve) Swarm.instance.dissolveOverlay(_glyphs);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    key: _key,
    opacity: _shown ? 1 : 0,
    duration: const Duration(milliseconds: 200),
    child: widget.child,
  );
}

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
  /// demora, la pantalla aparece igual) antes de mostrar la pantalla. Un
  /// máximo de 1,2 s se sentía como un corte; las letras que no llegaron se
  /// apagan solas sobre la pantalla ya visible.
  static const _minFlight = Duration(milliseconds: 300);
  static const _maxFlight = Duration(milliseconds: 750);
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
