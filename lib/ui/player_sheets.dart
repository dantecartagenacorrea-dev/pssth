import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:path_provider/path_provider.dart';

import '../core/app_exception.dart';
import '../data/bookmark_store.dart';
import '../domain/library_entry.dart';
import '../domain/search.dart';
import '../domain/summarizer.dart';
import '../playback/tts_audio_handler.dart';

void _snack(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

Future<void> showChaptersSheet(BuildContext context, TtsAudioHandler handler) {
  final chapters = handler.chapters;
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: chapters.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No se detectaron capítulos en este documento.'),
            )
          : ListView(
              shrinkWrap: true,
              children: [
                for (final c in chapters)
                  ListTile(
                    title: Text(c.title),
                    subtitle: Text('Página ${c.pageIndex + 1}'),
                    onTap: () {
                      handler.jumpToPage(c.pageIndex);
                      Navigator.pop(ctx);
                    },
                  ),
              ],
            ),
    ),
  );
}

Future<void> showSearchSheet(BuildContext context, TtsAudioHandler handler) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _SearchSheet(handler: handler),
  );
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.handler});
  final TtsAudioHandler handler;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  List<int> _hits = const [];
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final chunks = widget.handler.chunks;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar en el texto',
                  ),
                  onChanged: (v) => setState(() {
                    _query = v;
                    _hits = searchChunks(chunks, v);
                  }),
                ),
              ),
              Expanded(
                child: _hits.isEmpty
                    ? Center(
                        child: Text(_query.trim().isEmpty ? '' : 'Sin resultados'),
                      )
                    : ListView.builder(
                        itemCount: _hits.length,
                        itemBuilder: (_, i) {
                          final c = chunks[_hits[i]];
                          return ListTile(
                            title: Text(c.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text('Página ${c.pageIndex + 1}'),
                            onTap: () {
                              widget.handler.jumpToIndex(_hits[i]);
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> addBookmark(
  BuildContext context,
  TtsAudioHandler handler,
  BookmarkStore store,
  LibraryEntry entry,
) async {
  final c = handler.currentChunk;
  if (c == null) return;
  await store.add(
    documentId: entry.id,
    pageIndex: c.pageIndex,
    chunkIndex: c.chunkIndex,
    label: c.text,
  );
  if (context.mounted) _snack(context, 'Marcador guardado (página ${c.pageIndex + 1})');
}

Future<void> showBookmarksSheet(
  BuildContext context,
  TtsAudioHandler handler,
  BookmarkStore store,
  LibraryEntry entry,
) async {
  final list = await store.forDocument(entry.id);
  if (!context.mounted) return;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: list.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Aún no hay marcadores.'),
            )
          : StatefulBuilder(
              builder: (ctx, setSheet) => ListView(
                shrinkWrap: true,
                children: [
                  for (final b in List.of(list))
                    ListTile(
                      title: Text(b.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text('Página ${b.pageIndex + 1}'),
                      trailing: IconButton(
                        tooltip: 'Eliminar marcador',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await store.remove(b.id);
                          setSheet(() => list.removeWhere((x) => x.id == b.id));
                        },
                      ),
                      onTap: () {
                        handler.jumpToPosition(b.pageIndex, b.chunkIndex);
                        Navigator.pop(ctx);
                      },
                    ),
                ],
              ),
            ),
    ),
  );
}

/// Exporta el texto extraído a un .txt elegido por el usuario (no toca el original).
Future<void> exportText(
  BuildContext context,
  TtsAudioHandler handler,
  LibraryEntry entry,
) async {
  final chunks = handler.chunks;
  if (chunks.isEmpty) {
    _snack(context, 'No hay texto para exportar.');
    return;
  }
  final b = StringBuffer();
  final pages = handler.pages;
  if (pages.isNotEmpty) {
    // Texto original extraído, con sus saltos de línea.
    for (var i = 0; i < pages.length; i++) {
      final texto = pages[i].trim();
      if (texto.isEmpty) continue;
      if (b.isNotEmpty) b.write('\n\n');
      b.write('--- Página ${i + 1} ---\n\n$texto\n');
    }
  } else {
    var page = -1;
    for (final c in chunks) {
      if (c.pageIndex != page) {
        page = c.pageIndex;
        if (b.isNotEmpty) b.write('\n\n');
        b.write('--- Página ${page + 1} ---\n\n');
      }
      b.write('${c.text}\n\n');
    }
  }
  final dot = entry.name.lastIndexOf('.');
  final base = dot > 0 ? entry.name.substring(0, dot) : entry.name;
  try {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Exportar texto',
      fileName: '$base.txt',
      bytes: utf8.encode(b.toString()),
    );
    if (context.mounted && path != null) _snack(context, 'Texto exportado.');
  } catch (_) {
    if (context.mounted) _snack(context, 'No se pudo exportar el texto.');
  }
}

List<String> _summarize(String text) => summarizeExtractive(text);

/// Resumen extractivo local del documento; se puede escuchar.
Future<void> showSummarySheet(BuildContext context, TtsAudioHandler handler) async {
  final source = handler.pages.isNotEmpty
      ? handler.pages.join('\n\n')
      : handler.chunks.map((c) => c.text).join(' ');
  if (source.trim().isEmpty) {
    _snack(context, 'No hay texto para resumir.');
    return;
  }
  final future = compute(_summarize, source);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: FutureBuilder<List<String>>(
        future: future,
        builder: (ctx, snap) {
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final frases = snap.data!;
          if (frases.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text('El texto es demasiado corto para resumirlo.'),
            );
          }
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Resumen', style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Frases clave del propio texto, en su orden original.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final f in frases)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(f, style: Theme.of(ctx).textTheme.bodyLarge),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: () => handler.speakAside(frases.join(' ')),
                        icon: const Icon(Icons.volume_up),
                        label: const Text('Escuchar resumen'),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cerrar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
  await handler.stopAside();
}

/// "Compartir fragmento en audio": sintetiza la frase o la página actual con
/// la voz activa y la ofrece por la hoja Compartir (WhatsApp, Mensajes…).
/// Todo local: el audio se genera en el dispositivo y se borra al terminar.
Future<void> showShareAudioSheet(
  BuildContext context,
  TtsAudioHandler handler,
  LibraryEntry entry,
) async {
  if (handler.shareText().isEmpty) {
    _snack(context, 'No hay texto para compartir.');
    return;
  }
  final wholePage = await showModalBottomSheet<bool>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('Compartir como nota de voz')),
          ListTile(
            leading: const Icon(Icons.short_text),
            title: const Text('La frase actual'),
            onTap: () => Navigator.pop(ctx, false),
          ),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('La página actual'),
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    ),
  );
  if (wholePage == null || !context.mounted) return;
  _snack(context, 'Preparando el audio…');
  String? path;
  String? original;
  try {
    final dir = await getTemporaryDirectory();
    final base = '${dir.path}/lector_fragmento_${DateTime.now().millisecondsSinceEpoch}';
    path = await handler.renderShareAudio('$base.wav', wholePage: wholePage);
    if (path == null) throw AppException('Esta voz no permite guardar audio. Elige otra voz e inténtalo de nuevo.');
    if (Platform.isIOS) {
      // CAF/WAV no viajan bien como nota de voz; iOS los convierte a M4A.
      final m4a = await const MethodChannel('lector/audio_export')
          .invokeMethod<String>('toM4a', {'path': path, 'out': '$base.m4a'});
      if (m4a != null && m4a.isNotEmpty) {
        original = path;
        path = m4a;
      }
    }
    if (!context.mounted) return;
    final dot = entry.name.lastIndexOf('.');
    final titulo = dot > 0 ? entry.name.substring(0, dot) : entry.name;
    await const MethodChannel('lector/share').invokeMethod<bool>('shareFile', {
      'path': path,
      'text': 'Fragmento de "$titulo" leído con PSSTH!',
    });
  } catch (error) {
    if (context.mounted) _snack(context, '$error');
  } finally {
    for (final p in [path, original]) {
      if (p == null) continue;
      try {
        await File(p).delete();
      } catch (_) {}
    }
  }
}
