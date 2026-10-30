import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';

import '../core/app_exception.dart';
import '../core/motion.dart';
import '../data/bookmark_store.dart';
import '../data/highlight_store.dart';
import '../domain/library_entry.dart';
import '../domain/text_chunk.dart';
import '../domain/reading_window.dart';
import '../domain/voice_groups.dart';
import '../playback/tts_audio_handler.dart';
import 'audio_export_sheet.dart';
import 'immersive_reader.dart';
import 'pdf_editor_screen.dart';
import 'player_sheets.dart';
import 'premium.dart';
import 'quiz_screen.dart';
import 'read_scroll.dart';
import 'ether_text.dart';
import 'library_screen.dart' show showComfortSheet;
import 'swarm_transition.dart';

/// La velocidad como se escribe en español: "1,3×".
String speedLabel(double speed) => '${speed.toStringAsFixed(1).replaceAll('.', ',')}×';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key, required this.handler, required this.entry, required this.bookmarkStore});

  final TtsAudioHandler handler;
  final LibraryEntry entry;
  final BookmarkStore bookmarkStore;

  /// Opción del temporizador: pausar al terminar el capítulo.
  static const _chapterEnd = -1;

  // Con los colores que se eligieron en Aspecto (negro o blanco).
  @override
  Widget build(BuildContext context) => _ChromeVisibility(
    handler: handler,
    child: Builder(builder: _scaffold),
  );

  Widget _scaffold(BuildContext context) {
    return PremiumPage(
      largeTitle: false,
      titleWidget: const SizedBox.shrink(),
      actions: [
        PageAction(
          icon: CupertinoIcons.fullscreen,
          tooltip: 'Pantalla completa',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ImmersiveReader(handler: handler, entry: entry),
            ),
          ),
        ),
        PageAction(
          icon: CupertinoIcons.pencil_outline,
          tooltip: 'Subrayar la frase',
          onTap: () => highlightCurrent(context, handler),
        ),
        PageAction(
          icon: CupertinoIcons.bookmark,
          tooltip: 'Agregar marcador',
          onTap: () => addBookmark(context, handler, bookmarkStore, entry),
        ),
        PageAction(
          icon: CupertinoIcons.ellipsis,
          tooltip: 'Más opciones',
          primary: true,
          onTap: () => _showMore(context),
        ),
      ],
      body: _body(),
    );
  }

  /// Todo lo que no está a la vista, con su ícono, en una hoja.
  Future<void> _showMore(BuildContext context) async {
    final sleepOn = handler.sleepEndsAt.value != null || handler.sleepAtChapterEnd.value;
    final v = await showSwarmSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final (value, icon, label) in [
                ('capitulos', CupertinoIcons.list_bullet, 'Capítulos'),
                ('marcadores', CupertinoIcons.bookmark, 'Marcadores'),
                ('notas', CupertinoIcons.pencil_outline, 'Notas y subrayados'),
                ('historial', CupertinoIcons.clock, 'Lo que ya leíste'),
                ('sueno', sleepOn ? CupertinoIcons.moon_fill : CupertinoIcons.moon, 'Temporizador de sueño'),
                ('exportar', CupertinoIcons.doc_text, 'Exportar texto'),
                ('compartir', CupertinoIcons.share, 'Compartir fragmento en audio'),
                ('audio', CupertinoIcons.music_note, 'Exportar en audio'),
                if (entry.kind == 'pdf') ('editar', CupertinoIcons.pencil, 'Editar PDF'),
                ('aspecto', CupertinoIcons.paintbrush, 'Aspecto y letra'),
              ])
                ListTile(leading: Icon(icon), title: Text(label), onTap: () => Navigator.pop(ctx, value)),
            ],
          ),
        ),
      ),
    );
    if (v == null || !context.mounted) return;
    switch (v) {
      case 'capitulos':
        showChaptersSheet(context, handler);
      case 'marcadores':
        showBookmarksSheet(context, handler, bookmarkStore, entry);
      case 'notas':
        showHighlightsSheet(context, handler, entry);
      case 'historial':
        showReadScroll(context, handler);
      case 'sueno':
        await _showSleep(context);
      case 'exportar':
        exportText(context, handler, entry);
      case 'compartir':
        showShareAudioSheet(context, handler, entry);
      case 'audio':
        showAudioExportSheet(context, handler, entry);
      case 'editar':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PdfEditorScreen(path: entry.storedPath, title: entry.name),
          ),
        );
      case 'aspecto':
        showComfortSheet(context);
    }
  }

  Future<void> _showSleep(BuildContext context) async {
    final minutes = await showSwarmSheet<int>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (value, label) in const [
              (0, 'Sin temporizador'),
              (10, '10 minutos'),
              (20, '20 minutos'),
              (30, '30 minutos'),
              (60, '60 minutos'),
              (_chapterEnd, 'Al terminar el capítulo'),
            ])
              ListTile(title: Text(label), onTap: () => Navigator.pop(ctx, value)),
          ],
        ),
      ),
    );
    switch (minutes) {
      case null:
        return;
      case 0:
        handler.setSleepTimer(null);
      case _chapterEnd:
        handler.setSleepAtChapterEnd();
      default:
        handler.setSleepTimer(Duration(minutes: minutes));
    }
  }

  Widget _body() {
    return ValueListenableBuilder<PlayerSnapshot>(
      valueListenable: handler.snapshot,
      builder: (context, state, _) {
        final theme = Theme.of(context);
        final gray = theme.colorScheme.secondary;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentWidth(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Fade(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.pageCount <= 0 ? 'Página —' : 'Página ${state.pageIndex + 1} de ${state.pageCount}',
                          style: theme.textTheme.bodyMedium?.copyWith(color: gray),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          state.title.isEmpty ? entry.name : state.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 12),
                        // Lo más usado para estudiar, a la vista (antes solo en ⋮).
                        _StudyActions(
                          onSearch: () => showSearchSheet(context, handler),
                          onSummary: () => showSummarySheet(context, handler, entry),
                          onQuiz: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => QuizScreen(handler: handler, entry: entry),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Los controles flotan sobre el texto: el polvo de letras pasa por detrás.
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 18, 20, 300),
                          child: state.message == null && state.currentText.isNotEmpty
                              ? _ReadingView(handler: handler, index: handler.chunkIndex)
                              : Text(
                                  state.message ?? 'Toca Reproducir para escuchar.',
                                  style: theme.textTheme.bodyLarge?.copyWith(color: gray),
                                ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: _Fade(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                            // Los controles en la tarjeta oscura, como un reproductor de Apple.
                            child: HeroCard(
                              child: Builder(
                                builder: (context) => Column(
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
                                          icon: const Icon(CupertinoIcons.backward_end_fill, size: 26),
                                        ),
                                        IconButton(
                                          tooltip: 'Frase anterior',
                                          onPressed: state.hasText ? handler.skipToPrevious : null,
                                          icon: const Icon(CupertinoIcons.gobackward, size: 28),
                                        ),
                                        _PlayButton(
                                          playing: state.playing,
                                          enabled: state.hasText,
                                          onTap: () => state.playing ? handler.pause() : handler.play(),
                                        ),
                                        IconButton(
                                          tooltip: 'Frase siguiente',
                                          onPressed: state.hasText ? handler.skipToNext : null,
                                          icon: const Icon(CupertinoIcons.goforward, size: 28),
                                        ),
                                        IconButton(
                                          tooltip: 'Página siguiente',
                                          onPressed: state.hasText ? handler.nextPage : null,
                                          icon: const Icon(CupertinoIcons.forward_end_fill, size: 26),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _Pill(
                                            label: 'Velocidad',
                                            value: speedLabel(state.speed),
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
    // Solo el nombre legible ("Alex", "Voz ESD"), sin códigos técnicos.
    return voiceDisplayLabel(name: v.name, locale: v.locale, quality: v.quality).split(' · ').first;
  }

  /// Velocidad fina (de 0,1× en 0,1×) con las más usadas a un toque. Se
  /// aplica al soltar: se oye enseguida cómo queda.
  Future<void> _pickSpeed(BuildContext context, PlayerSnapshot state) async {
    var speed = state.speed;
    await showSwarmSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setSheet) {
            void choose(double v) {
              setSheet(() => speed = v);
              handler.setSpeed(v);
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Velocidad: ${speedLabel(speed)}', style: Theme.of(ctx).textTheme.titleLarge),
                  Slider(
                    value: speed.clamp(minSpeed, maxSpeed),
                    min: minSpeed,
                    max: maxSpeed,
                    divisions: ((maxSpeed - minSpeed) * 10).round(),
                    label: speedLabel(speed),
                    onChanged: (v) => setSheet(() => speed = (v * 10).round() / 10),
                    onChangeEnd: (v) => handler.setSpeed((v * 10).round() / 10),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final q in quickSpeeds)
                        ChoiceChip(label: Text(speedLabel(q)), selected: speed == q, onSelected: (_) => choose(q)),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Idioma del documento: automático o uno con voz instalada. Se recuerda.
  Future<void> _pickLanguage(BuildContext context) async {
    final manual = handler.manualLanguage;
    final langs = handler.availableLanguages.toList()..sort((a, b) => languageName(a).compareTo(languageName(b)));
    final v = await showSwarmSheet<String>(
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
                trailing: manual == null ? const Icon(CupertinoIcons.checkmark) : null,
                onTap: () => Navigator.pop(ctx, ''),
              ),
              for (final l in langs)
                ListTile(
                  title: Text(languageName(l)),
                  trailing: manual == l ? const Icon(CupertinoIcons.checkmark) : null,
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
    final v = await showSwarmSheet<String>(
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
                  if (voice.id == current) const Icon(CupertinoIcons.checkmark),
                  IconButton(
                    tooltip: fav ? 'Quitar de favoritas' : 'Marcar como favorita',
                    icon: Icon(fav ? CupertinoIcons.star_fill : CupertinoIcons.star),
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
                    trailing: current.isEmpty ? const Icon(CupertinoIcons.checkmark) : null,
                    onTap: () => Navigator.pop(ctx, ''),
                  ),
                  // Dora y Alex solo aparecen con el modelo instalado: se avisa dónde.
                  if (!hasNatural)
                    const ListTile(
                      leading: Icon(CupertinoIcons.sparkles),
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
                    leading: const Icon(CupertinoIcons.question_circle),
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
    showSwarmDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mejorar la voz'),
        content: Text(
          '${buena ? 'Ya estás usando una voz de alta calidad del sistema.' : 'La voz actual es la básica del sistema. Puedes instalar gratis una voz más natural:'}'
          '\n\n$pasos'
          '\n\nPSSTH! elige automáticamente la mejor voz instalada para el idioma del documento.',
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendido'))],
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
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: SwarmText(text)));
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

  // Al cambiar el tamaño de la letra o el espacio, el texto se mueve: se
  // vuelve a poner a la vista la frase que suena.
  final _style = Listenable.merge([Comfort.textSize, Comfort.lineHeight, Comfort.legible]);

  @override
  void initState() {
    super.initState();
    _style.addListener(_scrollToCurrent);
    _scrollToCurrent();
  }

  @override
  void dispose() {
    _style.removeListener(_scrollToCurrent);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _ReadingView old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _scrollToCurrent();
  }

  bool _marked(TextChunk c) => HighlightStore.instance?.isMarked(c.documentId, c.pageIndex, c.chunkIndex) ?? false;

  void _scrollToCurrent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[widget.index]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(ctx, alignment: 0.25, duration: const Duration(milliseconds: 300));
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // Tamaño y espacio entre renglones elegidos en Aspecto y letra, y las
    // frases que se subrayan.
    listenable: Listenable.merge([_style, ?HighlightStore.instance?.changes]),
    builder: (context, _) => _text(context),
  );

  Widget _text(BuildContext context) {
    final theme = Theme.of(context);
    final chunks = widget.handler.chunks;
    final (start, end) = readingWindow(total: chunks.length, index: widget.index);
    final base = theme.textTheme.bodyLarge?.copyWith(
      fontFamily: Comfort.readingFont,
      fontSize: Comfort.textSize.value,
      height: Comfort.lineHeight.value.height,
    );
    // Lo ya leído queda en blanco limpio, igual que lo que suena (no se apaga).
    final read = base;
    // Lo que viene no se ve: sus letras suben desde abajo y se arman (si se
    // viera tenue, taparía la reconstrucción).
    final hidden = base?.copyWith(color: Colors.transparent);
    final mark = theme.brightness == Brightness.dark ? const Color(0xFFFAC775) : const Color(0xFFBA7517);
    _keys.removeWhere((i, _) => i < start || i >= end);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = start; i < end; i++)
          Container(
            key: _keys.putIfAbsent(i, GlobalKey.new),
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 16),
            // Frase subrayada: una barra ámbar a la izquierda.
            decoration: _marked(chunks[i])
                ? BoxDecoration(
                    border: Border(left: BorderSide(color: mark, width: 3)),
                  )
                : null,
            // Solo el fragmento que suena y el siguiente se animan: lo ya leído
            // es texto quieto y lo que falta sigue en el documento (su río sube
            // desde abajo con los dos animados). Así la lectura va fluida.
            child: switch (i - widget.index) {
              < 0 => Text(chunks[i].text, style: read),
              > 1 => Text(chunks[i].text, style: hidden),
              // Misma estructura para el siguiente y el que suena: al pasar a
              // sonar, el fragmento conserva sus letras.
              final rel => Stack(
                children: [
                  Text(chunks[i].text, style: hidden),
                  EtherText(handler: widget.handler, text: chunks[i].text, style: base, relation: rel),
                ],
              ),
            },
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
    // Círculo lleno (blanco sobre la tarjeta oscura), como en la música de Apple.
    final s = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: playing ? 'Pausa' : 'Reproducir',
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: enabled ? 1 : 0.35,
        child: Material(
          color: s.primary,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: SizedBox(
              width: 64,
              height: 64,
              child: Icon(playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill, size: 28, color: s.onPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

/// Buscar, Resumen y Preguntas: botones chicos sobre el título.
class _StudyActions extends StatelessWidget {
  const _StudyActions({required this.onSearch, required this.onSummary, required this.onQuiz});
  final VoidCallback onSearch, onSummary, onQuiz;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 15),
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          style: style,
          onPressed: onSearch,
          icon: const Icon(CupertinoIcons.search, size: 18),
          label: const Text('Buscar'),
        ),
        OutlinedButton.icon(
          style: style,
          onPressed: onSummary,
          icon: const Icon(CupertinoIcons.sparkles, size: 18),
          label: const Text('Resumen'),
        ),
        OutlinedButton.icon(
          style: style,
          onPressed: onQuiz,
          icon: const Icon(CupertinoIcons.question_circle, size: 18),
          label: const Text('Preguntas'),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.value, required this.onTap, this.onLongPress});
  final String label;
  final String value;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Más angosta que esto, el nombre va sobre el valor.
  static const _narrow = 150.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final gray = scheme.secondary;
    final name = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: gray, fontWeight: FontWeight.w400),
    );
    final shown = Text(value, maxLines: 1, overflow: TextOverflow.ellipsis);
    return LayoutBuilder(
      // En un teléfono las tres no caben con nombre y valor lado a lado
      // ("Idioma Es…"): el nombre va arriba y el valor abajo.
      builder: (context, box) => FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.surfaceContainerHighest,
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.outline),
          padding: box.maxWidth < _narrow ? const EdgeInsets.symmetric(horizontal: 6, vertical: 6) : null,
        ),
        onPressed: onTap,
        onLongPress: onLongPress,
        child: box.maxWidth < _narrow
            ? Column(mainAxisSize: MainAxisSize.min, children: [name, shown])
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  name,
                  Flexible(child: shown),
                ],
              ),
      ),
    );
  }
}

/// Despeja la pantalla: la barra, el título y los controles se esconden a los
/// 3 segundos sin tocar mientras lee, y vuelven con cualquier toque o al
/// pausar. Con lector de pantalla, o si se pidió en Aspecto y letra, no se
/// esconden nunca.
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
      if (Comfort.keepControls.value) return;
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
