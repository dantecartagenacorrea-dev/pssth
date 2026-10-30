import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// Ancho del contenido: en el teléfono, toda la pantalla; en la tablet, el
/// 93 % (un margen fino a cada lado).
double contentWidth(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  return w < 700 ? w : w * 0.93;
}

/// Acción redonda de arriba a la derecha (lupa, campana, «+»).
class PageAction {
  const PageAction({required this.icon, required this.tooltip, required this.onTap, this.primary = false, this.child});

  /// Un botón que ya existe (un menú, un indicador), dentro del mismo círculo.
  const PageAction.widget(Widget this.child)
    : icon = CupertinoIcons.circle,
      tooltip = '',
      onTap = null,
      primary = false;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  /// La destacada: círculo lleno (el «+» de la referencia).
  final bool primary;

  /// En lugar del ícono (un menú propio, un indicador).
  final Widget? child;
}

/// Pantalla al estilo de Apple: arriba la vuelta atrás y las acciones en
/// círculos agrupados; un título grande; si hay, la tarjeta destacada con el
/// dato grande ([hero]); el contenido; y abajo la barra de pestañas.
class PremiumPage extends StatelessWidget {
  const PremiumPage({
    super.key,
    this.title,
    this.subtitle,
    this.titleWidget,
    this.leading,
    this.actions = const [],
    this.hero,
    required this.body,
    this.bottom,
    this.tabs,
    this.showBack = true,
    this.largeTitle = true,
  });

  final String? title;
  final String? subtitle;
  final Widget? titleWidget;
  final Widget? leading;
  final List<PageAction> actions;

  /// Lo destacado (el dato grande y sus píldoras), en una tarjeta oscura.
  final Widget? hero;
  final Widget body;

  /// Fijo abajo del contenido (controles).
  final Widget? bottom;

  /// Barra de pestañas de abajo (solo la pantalla principal).
  final List<TabItem>? tabs;
  final bool showBack;

  /// Título grande debajo de la barra (si no, va chico en la barra).
  final bool largeTitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final light = theme.brightness == Brightness.light;
    final canPop = showBack && Navigator.of(context).canPop();
    final heading = titleWidget ?? (title == null ? null : Text(title!));
    final bar = SizedBox(
      height: 56,
      child: Row(
        children: [
          if (leading != null)
            leading!
          else if (canPop)
            IconButton(
              tooltip: 'Volver',
              icon: const Icon(CupertinoIcons.chevron_back, size: 26),
              onPressed: () => Navigator.of(context).maybePop(),
            )
          else
            const SizedBox(width: 12),
          Expanded(
            child: largeTitle || heading == null
                ? const SizedBox.shrink()
                : DefaultTextStyle(
                    style: theme.textTheme.titleMedium!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    child: heading,
                  ),
          ),
          if (actions.isNotEmpty) _ActionGroup(actions: actions),
          const SizedBox(width: 12),
        ],
      ),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bar,
        if (largeTitle && heading != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: DefaultTextStyle(
              style: theme.textTheme.headlineLarge!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              child: heading,
            ),
          ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        if (hero case final h?)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: HeroCard(child: h),
          ),
        Expanded(child: body),
        ?bottom,
      ],
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(
          bottom: tabs == null,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentWidth(context)),
              child: content,
            ),
          ),
        ),
        bottomNavigationBar: tabs == null ? null : AppTabBar(items: tabs!),
      ),
    );
  }
}

/// Los círculos de arriba a la derecha, juntos en una píldora.
class _ActionGroup extends StatelessWidget {
  const _ActionGroup({required this.actions});
  final List<PageAction> actions;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: s.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, a) in actions.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            if (a.child case final w?)
              // Un botón propio (menú, indicador) con el mismo círculo.
              ClipOval(
                child: Material(
                  color: s.surfaceContainerHighest,
                  child: SizedBox.square(
                    dimension: 40,
                    child: IconButtonTheme(
                      data: IconButtonThemeData(
                        style: IconButton.styleFrom(
                          minimumSize: const Size(40, 40),
                          padding: EdgeInsets.zero,
                          iconSize: 20,
                          foregroundColor: s.onSurface,
                        ),
                      ),
                      child: Center(child: w),
                    ),
                  ),
                ),
              )
            else
              Tooltip(
                message: a.tooltip,
                child: Material(
                  color: a.primary ? s.onSurface : s.surfaceContainerHighest,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: a.onTap,
                    child: SizedBox.square(
                      dimension: 40,
                      child: Icon(a.icon, size: 20, color: a.primary ? s.surface : s.onSurface),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Tarjeta destacada: negra sobre el fondo blanco, gris oscuro sobre el negro,
/// siempre con texto blanco (como «Rate +124 Units»).
class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final onLight = Theme.of(context).brightness == Brightness.light;
    final family = DefaultTextStyle.of(context).style.fontFamily;
    final hero = AppTheme.hero(onLight: onLight);
    return Theme(
      data: family == null ? hero : AppTheme.withFont(hero, family),
      child: Builder(
        builder: (context) => Material(
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: Padding(padding: const EdgeInsets.fromLTRB(20, 18, 20, 18), child: child),
        ),
      ),
    );
  }
}

/// La rayita de arriba de las hojas.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36,
      height: 5,
      margin: const EdgeInsets.only(top: 8, bottom: 6),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.outline, borderRadius: BorderRadius.circular(3)),
    ),
  );
}

/// Píldora sobre la tarjeta oscura: ícono y texto con borde fino.
class HeroPill extends StatelessWidget {
  const HeroPill({super.key, this.icon, required this.label, this.onTap, this.tooltip, this.selected = false});
  final IconData? icon;
  final String label;
  final VoidCallback? onTap;
  final String? tooltip;

  /// Llena en blanco (la opción elegida, «6 Units»).
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Premium.hero : Premium.heroText;
    final pill = Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Material(
        color: selected ? Premium.heroText : Premium.pillFill,
        shape: const StadiumBorder(side: BorderSide(color: Premium.pillBorder)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 7)],
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: AppTheme.font,
                    color: fg,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return tooltip == null ? pill : Tooltip(message: tooltip, child: pill);
  }
}

/// Botón redondo grande sobre la tarjeta oscura (reproducir).
class HeroRoundButton extends StatelessWidget {
  const HeroRoundButton({super.key, required this.icon, required this.tooltip, this.onTap, this.size = 56});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: Premium.heroText,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox.square(
          dimension: size,
          child: Icon(icon, color: Premium.hero, size: size * 0.46),
        ),
      ),
    ),
  );
}

/// Barra de pestañas de Apple: ícono y nombre, la elegida resaltada.
class AppTabBar extends StatelessWidget {
  const AppTabBar({super.key, required this.items});
  final List<TabItem> items;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: s.surface,
        border: Border(top: BorderSide(color: s.outline, width: 0.6)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentWidth(context)),
            child: SizedBox(
              height: 58,
              child: Row(
                children: [
                  for (final item in items)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: item.selected,
                        label: item.label,
                        excludeSemantics: true,
                        child: InkWell(
                          onTap: item.onTap,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(item.icon, size: 25, color: item.selected ? s.onSurface : s.onSurfaceVariant),
                              const SizedBox(height: 3),
                              Text(
                                item.label,
                                style: t.labelMedium?.copyWith(
                                  fontSize: 11,
                                  color: item.selected ? s.onSurface : s.onSurfaceVariant,
                                  fontWeight: item.selected ? FontWeight.w600 : FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TabItem {
  const TabItem({required this.icon, required this.label, required this.onTap, this.selected = false});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;
}

/// Ícono dentro de un círculo gris (como los logos de la lista de movimientos).
class IconAvatar extends StatelessWidget {
  const IconAvatar(this.icon, {super.key, this.size = 44});
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: s.surfaceContainerHighest, shape: BoxShape.circle),
      child: Icon(icon, size: size * 0.46, color: s.onSurface),
    );
  }
}

/// Rótulo de sección («Hoy», «27 de octubre»), en gris.
class SectionCaption extends StatelessWidget {
  const SectionCaption(this.text, {super.key, this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 6)});
  final String text;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Text(text, style: Theme.of(context).textTheme.labelSmall),
  );
}

/// Recuadro de acción con ícono arriba y texto abajo.
class ActionTile extends StatelessWidget {
  const ActionTile({super.key, required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Material(
      color: s.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Premium.radiusCard)),
      child: InkWell(
        borderRadius: BorderRadius.circular(Premium.radiusCard),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: s.onSurface),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 13, color: s.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
