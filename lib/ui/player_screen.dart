import 'package:flutter/material.dart';

import '../core/app_exception.dart';
import '../data/bookmark_store.dart';
import '../domain/library_entry.dart';
import '../playback/tts_audio_handler.dart';
import 'player_sheets.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lector'),
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
                case 'exportar':
                  exportText(context, handler, entry);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'buscar', child: Text('Buscar en el texto')),
              PopupMenuItem(value: 'capitulos', child: Text('Capítulos')),
              PopupMenuItem(value: 'marcadores', child: Text('Marcadores')),
              PopupMenuItem(value: 'exportar', child: Text('Exportar texto')),
            ],
          ),
        ],
      ),
      body: ValueListenableBuilder<PlayerSnapshot>(
        valueListenable: handler.snapshot,
        builder: (context, state, _) {
          return Center(
            child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
            child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  state.title.isEmpty ? entry.name : state.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  state.pageCount <= 0
                      ? 'Página —'
                      : 'Página ${state.pageIndex + 1} / ${state.pageCount}',
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: state.hasText ? state.progress : 0),
                const SizedBox(height: 16),
                Expanded(
                  child: SingleChildScrollView(
                    child: state.message == null && state.currentText.isNotEmpty
                        ? _HighlightedText(handler: handler, text: state.currentText)
                        : Text(
                            state.message ?? 'Pulsa Play para escuchar.',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      tooltip: 'Página anterior',
                      onPressed: state.hasText ? handler.previousPage : null,
                      icon: const Icon(Icons.fast_rewind, size: 32),
                    ),
                    IconButton(
                      tooltip: 'Frase anterior',
                      onPressed: state.hasText ? handler.skipToPrevious : null,
                      icon: const Icon(Icons.skip_previous, size: 36),
                    ),
                    IconButton(
                      tooltip: state.playing ? 'Pausa' : 'Play',
                      onPressed: !state.hasText
                          ? null
                          : () {
                              if (state.playing) {
                                handler.pause();
                              } else {
                                handler.play();
                              }
                            },
                      icon: Icon(
                        state.playing ? Icons.pause_circle : Icons.play_circle,
                        size: 64,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Frase siguiente',
                      onPressed: state.hasText ? handler.skipToNext : null,
                      icon: const Icon(Icons.skip_next, size: 36),
                    ),
                    IconButton(
                      tooltip: 'Página siguiente',
                      onPressed: state.hasText ? handler.nextPage : null,
                      icon: const Icon(Icons.fast_forward, size: 32),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Text('Velocidad'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<double>(
                        isExpanded: true,
                        value: state.speed,
                        items: speeds
                            .map(
                              (s) => DropdownMenuItem(
                                value: s,
                                child: Text('$s×'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            handler.setSpeed(value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('Voz'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _voiceValue(state),
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Voz del sistema'),
                          ),
                          ...state.voices.map(
                            (v) => DropdownMenuItem(
                              value: v.id,
                              child: Text(v.label, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null || value.isEmpty) {
                            handler.setVoice(null);
                            return;
                          }
                          final voice = state.voices.where((v) => v.id == value);
                          if (voice.isNotEmpty) {
                            handler.setVoice(voice.first);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          )));
        },
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

/// Muestra el bloque actual y resalta la palabra leída (cuando el texto de voz
/// coincide con el original; si no, se muestra sin resaltar).
class _HighlightedText extends StatelessWidget {
  const _HighlightedText({required this.handler, required this.text});
  final TtsAudioHandler handler;
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge;
    return ValueListenableBuilder<(int, int)?>(
      valueListenable: handler.wordRange,
      builder: (context, range, _) {
        final spoken = handler.currentChunk?.speech;
        if (range == null ||
            spoken != text ||
            range.$1 < 0 ||
            range.$2 > text.length ||
            range.$1 >= range.$2) {
          return Text(text, style: style);
        }
        return Text.rich(
          TextSpan(
            style: style,
            children: [
              TextSpan(text: text.substring(0, range.$1)),
              TextSpan(
                text: text.substring(range.$1, range.$2),
                style: TextStyle(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextSpan(text: text.substring(range.$2)),
            ],
          ),
        );
      },
    );
  }
}
