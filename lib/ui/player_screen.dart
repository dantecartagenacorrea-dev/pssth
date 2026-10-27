import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../core/app_exception.dart';
import '../data/bookmark_store.dart';
import '../domain/library_entry.dart';
import '../domain/reading_window.dart';
import '../domain/voice_groups.dart';
import '../playback/tts_audio_handler.dart';
import '../theme/app_theme.dart';
import 'player_sheets.dart';
import 'ether_text.dart';

/// Ancho máximo del contenido (iPad/macOS); en iPhone no interviene.
const double kMaxContentWidth = 720;

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({
    super.key,
    required this.handler,
    required this.entry,
    required this.bookmarkStore,
  });

  final TtsAudioHandler handler;
  final LibraryEntry entry;
  final BookmarkStore bookmarkStore;

  // El reproductor va siempre en oscuro: las letras "en el éter" lucen sobre
  // fondo nocturno, sin importar el tema del sistema.
  @override
  Widget build(BuildContext context) => Theme(data: AppTheme.dark(), child: _ChromeVisibility(handler: handler, child: Builder(builder: _scaffold)));

  Widget _scaffold(BuildContext context) {
    return Scaffold(
      // Sin barras opacas: el éter llega hasta los bordes de la pantalla.
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.black,
      appBar: PreferredSize(preferredSize: const Size.fromHeight(kToolbarHeight), child: _Fade(child: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/branding/logo.png', height: 30),
            const SizedBox(width: 8),
            const Text('PSSTH!'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Agregar marcador',
            icon: const Icon(Icons.bookmark_add_outlined),
            onPressed: () => addBookmark(context, handler, bookmarkStore, entry),
          ),
          ValueListenableBuilder<DateTime?>(
            valueListenable: handler.sleepEndsAt,
            builder: (context, ends, _) => PopupMenuButton<int>(
              tooltip: 'Temporizador de sueño',
              icon: Icon(ends == null ? Icons.bedtime_outlined : Icons.bedtime),
              onSelected: (minutes) => handler.setSleepTimer(
                minutes == 0 ? null : Duration(minutes: minutes),
              ),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 0, child: Text('Sin temporizador')),
                PopupMenuItem(value: 10, child: Text('10 minutos')),
                PopupMenuItem(value: 20, child: Text('20 minutos')),
                PopupMenuItem(value: 30, child: Text('30 minutos')),
                PopupMenuItem(value: 60, child: Text('60 minutos')),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Más opciones',
            onSelected: (v) {
              switch (v) {
                case 'buscar':
                  showSearchSheet(context, handler);
                case 'capitulos':
                  showChaptersSheet(context, handler);
                case 'marcadores':
                  showBookmarksSheet(context, handler, bookmarkStore, entry);
                case 'resumen':
                  showSummarySheet(context, handler, entry);
                case 'exportar':
                  exportText(context, handler, entry);
                case 'compartir':
                  showShareAudioSheet(context, handler, entry);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'buscar', child: Text('Buscar en el texto')),
              PopupMenuItem(value: 'capitulos', child: Text('Capítulos')),
              PopupMenuItem(value: 'marcadores', child: Text('Marcadores')),
              PopupMenuItem(value: 'resumen', child: Text('Resumen del texto')),
              PopupMenuItem(value: 'exportar', child: Text('Exportar texto')),
              PopupMenuItem(value: 'compartir', child: Text('Compartir fragmento en audio')),
            ],
          ),
        ],
      ),),),
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + kToolbarHeight),
            child: _body(),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    return ValueListenableBuilder<PlayerSnapshot>(
        valueListenable: handler.snapshot,
        builder: (context, state, _) {
          final theme = Theme.of(context);
          final gray = theme.colorScheme.secondary;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Fade(child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.name.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          state.title.isEmpty ? entry.name : state.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineSmall,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          state.pageCount <= 0
                              ? 'Página —'
                              : 'Página ${state.pageIndex + 1} de ${state.pageCount}',
                          style: TextStyle(fontSize: 15, color: gray),
                        ),
                      ],
                    ),
                  ),),
                  // Los controles flotan sobre el texto: el polvo de letras pasa por detrás.
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 22, 24, 260),
                      child: state.message == null && state.currentText.isNotEmpty
                          ? _ReadingView(handler: handler, index: handler.chunkIndex)
                          : Text(
                              state.message ?? 'Pulsa Play para escuchar.',
                              style: theme.textTheme.bodyLarge?.copyWith(color: gray),
                            ),
                    ),
                        ),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: _Fade(child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    // Controles sin fondo: flotan sobre la luz y el polvo.
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: Material(
                        type: MaterialType.transparency,
                        child: Card(
                      color: Colors.transparent,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                minHeight: 4,
                                value: state.hasText ? state.progress : 0,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  tooltip: 'Página anterior',
                                  onPressed: state.hasText ? handler.previousPage : null,
                                  icon: const Icon(Icons.skip_previous_rounded, size: 26),
                                ),
                                IconButton(
                                  tooltip: 'Frase anterior',
                                  onPressed: state.hasText ? handler.skipToPrevious : null,
                                  icon: const Icon(Icons.replay_rounded, size: 28),
                                ),
                                _PlayButton(
                                  playing: state.playing,
                                  enabled: state.hasText,
                                  onTap: () => state.playing ? handler.pause() : handler.play(),
                                ),
                                IconButton(
                                  tooltip: 'Frase siguiente',
                                  onPressed: state.hasText ? handler.skipToNext : null,
                                  icon: const Icon(Icons.forward_rounded, size: 28),
                                ),
                                IconButton(
                                  tooltip: 'Página siguiente',
                                  onPressed: state.hasText ? handler.nextPage : null,
                                  icon: const Icon(Icons.skip_next_rounded, size: 26),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _Pill(
                                    label: 'Velocidad',
                                    value: '${state.speed}×',
                                    onTap: () => _pickSpeed(context, state),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _Pill(
                                    label: 'Idioma',
                                    value: languageName(handler.documentLanguage ?? 'es'),
                                    onTap: () => _pickLanguage(context),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _Pill(
                                    label: 'Voz',
                                    value: _voiceLabel(state),
                                    onTap: () => _pickVoice(context, state),
                                    onLongPress: () => _showVoiceHelp(context, state),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    ),
                      ),
                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
  }

  String _voiceLabel(PlayerSnapshot state) {
    final id = _voiceValue(state);
    if (id.isEmpty) return 'Sistema';
    final v = state.voices.firstWhere((v) => v.id == id);
    final label = v.label.split('(').first.trim();
    return label.isEmpty ? v.label : label;
  }

  Future<void> _pickSpeed(BuildContext context, PlayerSnapshot state) async {
    final v = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final s in speeds)
              ListTile(
                title: Text('$s×'),
                trailing: s == state.speed ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (v != null) handler.setSpeed(v);
  }

  /// Idioma del documento: automático o uno con voz instalada. Se recuerda.
  Future<void> _pickLanguage(BuildContext context) async {
    final manual = handler.manualLanguage;
    final langs = handler.availableLanguages.toList()..sort((a, b) => languageName(a).compareTo(languageName(b)));
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: const Text('Automático'),
                subtitle: const Text('Lo detecta según el texto'),
                trailing: manual == null ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(ctx, ''),
              ),
              for (final l in langs)
                ListTile(
                  title: Text(languageName(l)),
                  trailing: manual == l ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.pop(ctx, l),
                ),
            ],
          ),
        ),
      ),
    );
    if (v == null) return;
    await handler.setManualLanguage(v.isEmpty ? null : v);
  }

  Future<void> _pickVoice(BuildContext context, PlayerSnapshot state) async {
    final current = _voiceValue(state);
    final store = handler.settingsStore;
    final favorites = await store.loadFavoriteVoices();
    final uses = await store.loadVoiceUses();
    if (!context.mounted) return;
    final hasNatural = state.voices.any((v) => v.quality == 'natural');
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          // Agrupadas: favoritas, más usadas, recomendadas, el idioma del
          // documento y el resto plegado.
          final groups = groupVoices<VoiceOption>(
            state.voices,
            preferredLanguage: handler.documentLanguage ?? 'es',
            name: (v) => v.name,
            locale: (v) => v.locale,
            quality: (v) => v.quality,
            id: (v) => v.id,
            favorites: favorites,
            uses: uses,
          );
          Widget tile(VoiceOption voice) {
            final fav = favorites.contains(voice.id);
            return ListTile(
              title: Text(
                voiceDisplayLabel(name: voice.name, locale: voice.locale, quality: voice.quality),
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (voice.id == current) const Icon(Icons.check_rounded),
                  IconButton(
                    tooltip: fav ? 'Quitar de favoritas' : 'Marcar como favorita',
                    icon: Icon(fav ? Icons.star_rounded : Icons.star_border_rounded),
                    onPressed: () {
                      setSheet(() => fav ? favorites.remove(voice.id) : favorites.add(voice.id));
                      store.saveFavoriteVoices(favorites);
                    },
                  ),
                ],
              ),
              onTap: () => Navigator.pop(ctx, voice.id),
            );
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    title: const Text('Automática (la mejor para el idioma)'),
                    trailing: current.isEmpty ? const Icon(Icons.check_rounded) : null,
                    onTap: () => Navigator.pop(ctx, ''),
                  ),
                  // Dora y Alex solo aparecen con el modelo instalado: se avisa dónde.
                  if (!hasNatural)
                    const ListTile(
                      leading: Icon(Icons.auto_awesome_rounded),
                      title: Text('Dora y Alex (voces naturales)'),
                      subtitle: Text('Instálalas desde la pantalla principal: menú ⋮ → Voces y modelos.'),
                    ),
                  for (final g in groups)
                    if (g.expanded) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Text(g.title, style: Theme.of(ctx).textTheme.titleSmall),
                      ),
                      for (final voice in g.voices) tile(voice),
                    ] else
                      ExpansionTile(
                        title: Text('${g.title} (${g.voices.length})'),
                        children: [for (final voice in g.voices) tile(voice)],
                      ),
                  ListTile(
                    leading: const Icon(Icons.help_outline_rounded),
                    title: const Text('Mejorar la voz'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showVoiceHelp(context, state);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (v == null) return;
    if (v.isEmpty) {
      handler.setVoice(null);
      return;
    }
    final voice = state.voices.where((x) => x.id == v);
    if (voice.isEmpty) return;
    handler.setVoice(voice.first);
    store.countVoiceUse(v);
  }

  /// Cómo conseguir gratis voces de mayor calidad (son del sistema, no de Lector).
  void _showVoiceHelp(BuildContext context, PlayerSnapshot state) {
    final active = state.voices.where((v) => v.id == state.selectedVoiceId);
    final q = active.isEmpty ? null : active.first.quality?.toLowerCase();
    final buena = q != null && (q.contains('premium') || q.contains('enhanced') || q.contains('high'));
    final pasos = Platform.isIOS
        ? 'Ajustes → Accesibilidad → Contenido hablado → Voces → Español → '
            'descarga una voz "Mejorada" o "Premium" (gratis, unos 100–300 MB). '
            'Después elígela aquí en "Voz".'
        : 'Ajustes → Sistema (o Accesibilidad) → Salida de texto a voz → '
            'Motor de Google → Instalar datos de voz → Español → descarga una voz de alta calidad (gratis). '
            'Después elígela aquí en "Voz".';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mejorar la voz'),
        content: Text(
          '${buena ? 'Ya estás usando una voz de alta calidad del sistema.' : 'La voz actual es la básica del sistema. Puedes instalar gratis una voz más natural:'}'
          '\n\n$pasos'
          '\n\nPSSTH! elige automáticamente la mejor voz instalada para el idioma del documento.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido')),
        ],
      ),
    );
  }

  String _voiceValue(PlayerSnapshot state) {
    final id = state.selectedVoiceId;
    if (id == null) {
      return '';
    }
    final exists = state.voices.any((v) => v.id == id);
    return exists ? id : '';
  }
}

void showSafeMessage(BuildContext context, Object error) {
  final text = error is AppException ? error.message : 'Ocurrió un problema. Inténtalo de nuevo.';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

/// Varios fragmentos alrededor del que se lee, para seguir el texto: el actual
/// resaltado (con la palabra, si la voz la informa) y la vista se desplaza sola.
class _ReadingView extends StatefulWidget {
  const _ReadingView({required this.handler, required this.index});
  final TtsAudioHandler handler;
  final int index;

  @override
  State<_ReadingView> createState() => _ReadingViewState();
}

class _ReadingViewState extends State<_ReadingView> {
  // Una llave por fragmento: cada uno conserva sus letras al moverse la ventana.
  final _keys = <int, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _scrollToCurrent();
  }

  @override
  void didUpdateWidget(covariant _ReadingView old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _scrollToCurrent();
  }

  void _scrollToCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[widget.index]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(ctx, alignment: 0.25, duration: const Duration(milliseconds: 300));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chunks = widget.handler.chunks;
    final (start, end) = readingWindow(total: chunks.length, index: widget.index);
    final base = theme.textTheme.bodyLarge?.copyWith(fontSize: 19, height: 1.45);
    final dim = base?.copyWith(color: theme.colorScheme.secondary);
    _keys.removeWhere((i, _) => i < start || i >= end);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = start; i < end; i++)
          Padding(
            key: _keys.putIfAbsent(i, GlobalKey.new),
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 16),
            child: EtherText(
              handler: widget.handler,
              text: chunks[i].text,
              style: i < widget.index ? dim : base,
              relation: i - widget.index,
            ),
          ),
      ],
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.enabled, required this.onTap});
  final bool playing;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = Theme.of(context).colorScheme.surface;
    final bg = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      label: playing ? 'Pausa' : 'Play',
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1 : 0.35,
        child: Material(
          color: bg,
          shape: const CircleBorder(),
          elevation: 6,
          shadowColor: Colors.black26,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: SizedBox(
              width: 72,
              height: 72,
              child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 34, color: fg),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.value, required this.onTap, this.onLongPress});
  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gray = scheme.secondary;
    return FilledButton(
      style: FilledButton.styleFrom(backgroundColor: Colors.transparent),
      onPressed: onTap,
      onLongPress: onLongPress,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: gray, fontWeight: FontWeight.w400)),
          Flexible(child: Text(value, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

/// Despeja la pantalla: la barra, el título y los controles se esconden a los
/// 3 segundos sin tocar mientras lee, y vuelven con cualquier toque o al
/// pausar. Con lector de pantalla no se esconden nunca.
class _ChromeVisibility extends StatefulWidget {
  const _ChromeVisibility({required this.handler, required this.child});
  final TtsAudioHandler handler;
  final Widget child;

  @override
  State<_ChromeVisibility> createState() => _ChromeVisibilityState();
}

class _ChromeVisibilityState extends State<_ChromeVisibility> {
  static const _hideAfter = Duration(seconds: 3);
  final _visible = ValueNotifier(true);
  Timer? _timer;
  bool _wasPlaying = false;

  @override
  void initState() {
    super.initState();
    widget.handler.snapshot.addListener(_onPlayback);
    _onPlayback();
  }

  void _onPlayback() {
    final playing = widget.handler.snapshot.value.playing;
    if (playing == _wasPlaying) return;
    _wasPlaying = playing;
    if (playing) {
      _restart();
    } else {
      _timer?.cancel();
      _visible.value = true;
    }
  }

  void _restart() {
    _timer?.cancel();
    _timer = Timer(_hideAfter, () {
      if (!mounted || !_wasPlaying || MediaQuery.accessibleNavigationOf(context)) return;
      _visible.value = false;
    });
  }

  void _touch() {
    _visible.value = true;
    _restart();
  }

  @override
  void dispose() {
    widget.handler.snapshot.removeListener(_onPlayback);
    _timer?.cancel();
    _visible.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _touch(),
        child: _ChromeScope(notifier: _visible, child: widget.child),
      );
}

class _ChromeScope extends InheritedNotifier<ValueNotifier<bool>> {
  const _ChromeScope({required super.notifier, required super.child});
}

/// Aparece y desaparece con la barra y los controles; escondido no recibe toques.
class _Fade extends StatelessWidget {
  const _Fade({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shown = context.dependOnInheritedWidgetOfExactType<_ChromeScope>()?.notifier?.value ?? true;
    return IgnorePointer(
      ignoring: !shown,
      child: AnimatedOpacity(opacity: shown ? 1 : 0, duration: const Duration(milliseconds: 400), child: child),
    );
  }
}
