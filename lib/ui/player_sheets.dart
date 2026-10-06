import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/bookmark_store.dart';
import '../domain/library_entry.dart';
import '../domain/search.dart';
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
