import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:path_provider/path_provider.dart';

import '../core/app_exception.dart';
import '../data/bookmark_store.dart';
import '../data/highlight_store.dart';
import '../domain/highlight.dart';
import '../domain/library_entry.dart';
import '../domain/search.dart';
import '../playback/tts_audio_handler.dart';
import 'study_sheets.dart';
import 'swarm_transition.dart';

void _snack(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: SwarmText(m)));

/// El aviso de un error: el mensaje propio si es nuestro ([AppException]);
/// si no, [fallback] (nunca el texto técnico de la excepción).
String _say(Object error, String fallback) => error is AppException ? error.message : fallback;

Future<void> showChaptersSheet(BuildContext context, TtsAudioHandler handler) {
  final chapters = handler.chapters;
  return showSwarmSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: chapters.isEmpty
          ? const Padding(padding: EdgeInsets.all(24), child: Text('No se detectaron capítulos en este documento.'))
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
  return showSwarmSheet(
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
                  decoration: const InputDecoration(prefixIcon: Icon(CupertinoIcons.search), hintText: 'Buscar en el texto'),
                  onChanged: (v) => setState(() {
                    _query = v;
                    _hits = searchChunks(chunks, v);
                  }),
                ),
              ),
              Expanded(
                child: _hits.isEmpty
                    ? Center(child: Text(_query.trim().isEmpty ? '' : 'Sin resultados'))
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

Future<void> addBookmark(BuildContext context, TtsAudioHandler handler, BookmarkStore store, LibraryEntry entry) async {
  final c = handler.currentChunk;
  if (c == null) return;
  await store.add(documentId: entry.id, pageIndex: c.pageIndex, chunkIndex: c.chunkIndex, label: c.text);
  if (context.mounted) _snack(context, 'Marcador guardado (página ${c.pageIndex + 1})');
}

Future<void> showBookmarksSheet(
  BuildContext context,
  TtsAudioHandler handler,
  BookmarkStore store,
  LibraryEntry entry,
) async {
  final list = await store.forDocument(entry.id);
  final gone = <String>{}; // borrados en este panel, que todavía se pueden deshacer
  if (!context.mounted) return;
  await showSwarmSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: list.isEmpty
          ? const Padding(padding: EdgeInsets.all(24), child: Text('Aún no hay marcadores.'))
          : StatefulBuilder(
              builder: (ctx, setSheet) => ListView(
                shrinkWrap: true,
                children: [
                  for (final b in List.of(list))
                    // Borrado: queda su lugar con "Deshacer" (un aviso abajo
                    // quedaría tapado por este panel).
                    if (gone.contains(b.id))
                      ListTile(
                        title: const Text('Marcador eliminado'),
                        subtitle: Text('Página ${b.pageIndex + 1}'),
                        trailing: TextButton(
                          onPressed: () async {
                            final back = await store.add(
                              documentId: b.documentId,
                              pageIndex: b.pageIndex,
                              chunkIndex: b.chunkIndex,
                              label: b.label,
                            );
                            setSheet(() {
                              gone.remove(b.id);
                              list[list.indexWhere((x) => x.id == b.id)] = back;
                            });
                          },
                          child: const Text('Deshacer'),
                        ),
                      )
                    else
                      ListTile(
                        title: Text(b.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text('Página ${b.pageIndex + 1}'),
                        trailing: IconButton(
                          tooltip: 'Eliminar marcador',
                          icon: const Icon(CupertinoIcons.trash),
                          onPressed: () async {
                            await store.remove(b.id);
                            setSheet(() => gone.add(b.id));
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

/// Subraya la frase que suena; si ya estaba subrayada, abre su nota.
Future<void> highlightCurrent(BuildContext context, TtsAudioHandler handler) async {
  final store = HighlightStore.instance;
  final c = handler.currentChunk;
  if (store == null || c == null) return;
  final existing = await store.find(c.documentId, c.pageIndex, c.chunkIndex);
  if (!context.mounted) return;
  if (existing != null) return editHighlightNote(context, existing);
  final h = await store.add(documentId: c.documentId, pageIndex: c.pageIndex, chunkIndex: c.chunkIndex, text: c.text);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const SwarmText('Frase subrayada'),
      action: SnackBarAction(label: 'Agregar nota', onPressed: () => editHighlightNote(context, h)),
    ),
  );
}

/// Escribir o cambiar la nota de un subrayado, o quitarlo.
Future<void> editHighlightNote(BuildContext context, Highlight h) async {
  final store = HighlightStore.instance;
  if (store == null) return;
  final controller = TextEditingController(text: h.note);
  const remove = '\u0000quitar';
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Nota · página ${h.pageIndex + 1}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(h.text, maxLines: 4, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(hintText: 'Escribe tu nota'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, remove), child: const Text('Quitar subrayado')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Guardar')),
      ],
    ),
  );
  controller.dispose();
  if (result == null) return;
  if (result == remove) {
    await store.remove(h.id);
  } else {
    await store.setNote(h.id, result);
  }
}

/// Las frases subrayadas del documento con sus notas: saltar a cada una,
/// editar la nota, quitarla o exportarlas todas como texto.
Future<void> showHighlightsSheet(BuildContext context, TtsAudioHandler handler, LibraryEntry entry) async {
  final store = HighlightStore.instance;
  if (store == null) return;
  await showSwarmSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ValueListenableBuilder<int>(
        valueListenable: store.changes,
        builder: (ctx, _, _) => FutureBuilder<List<Highlight>>(
          future: store.forDocument(entry.id),
          builder: (ctx, snap) {
            final list = snap.data;
            if (list == null) return const SizedBox(height: 120);
            if (list.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Aún no hay frases subrayadas. Toca el subrayador mientras escuchas.'),
              );
            }
            return ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: Text('Notas y subrayados (${list.length})'),
                  trailing: TextButton.icon(
                    icon: const Icon(CupertinoIcons.arrow_down_doc),
                    label: const Text('Exportar'),
                    onPressed: () => _exportHighlights(ctx, entry, list),
                  ),
                ),
                for (final h in list)
                  ListTile(
                    title: Text(h.text, maxLines: 3, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      h.note.isEmpty ? 'Página ${h.pageIndex + 1}' : 'Página ${h.pageIndex + 1} · ${h.note}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: 'Editar nota',
                      icon: const Icon(CupertinoIcons.square_pencil),
                      onPressed: () => editHighlightNote(ctx, h),
                    ),
                    onTap: () {
                      handler.jumpToPosition(h.pageIndex, h.chunkIndex);
                      Navigator.pop(ctx);
                    },
                  ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

Future<void> _exportHighlights(BuildContext context, LibraryEntry entry, List<Highlight> list) async {
  final dot = entry.name.lastIndexOf('.');
  final base = dot > 0 ? entry.name.substring(0, dot) : entry.name;
  try {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Exportar notas',
      fileName: 'Notas - $base.txt',
      bytes: utf8.encode(highlightsAsText(base, list)),
    );
    if (context.mounted && path != null) _snack(context, 'Notas exportadas.');
  } catch (_) {
    if (context.mounted) _snack(context, 'No se pudieron exportar las notas.');
  }
}

/// Exporta el texto extraído a un .txt elegido por el usuario (no toca el original).
Future<void> exportText(BuildContext context, TtsAudioHandler handler, LibraryEntry entry) async {
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

/// Resumen del documento: con la IA del equipo si está disponible (conceptos,
/// ideas y resumen breve); si no, el extractivo local. Se puede escuchar y
/// descargar.
Future<void> showSummarySheet(BuildContext context, TtsAudioHandler handler, LibraryEntry entry) async {
  final source = handler.pages.isNotEmpty ? handler.pages.join('\n\n') : handler.chunks.map((c) => c.text).join(' ');
  if (source.trim().isEmpty) {
    _snack(context, 'No hay texto para resumir.');
    return;
  }
  // Siempre el resumen para estudiar: con la IA del equipo si la hay y, si
  // no, armado con las palabras y frases que más pesan en el texto.
  return showStudySummarySheet(context, handler, entry);
}

/// Descarga el resumen como texto (.txt) o como audio con la voz activa.
Future<void> downloadSummary(
  BuildContext context,
  TtsAudioHandler handler,
  LibraryEntry entry,
  List<String> frases,
) async {
  final comoAudio = await showSwarmSheet<bool>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('Descargar resumen')),
          ListTile(
            leading: const Icon(CupertinoIcons.doc_text),
            title: const Text('Como texto (.txt)'),
            onTap: () => Navigator.pop(ctx, false),
          ),
          ListTile(
            leading: const Icon(CupertinoIcons.music_note),
            title: const Text('Como audio, con la voz actual'),
            onTap: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    ),
  );
  if (comoAudio == null || !context.mounted) return;
  final dot = entry.name.lastIndexOf('.');
  final titulo = dot > 0 ? entry.name.substring(0, dot) : entry.name;
  if (!comoAudio) {
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Descargar resumen',
        fileName: 'Resumen - $titulo.txt',
        bytes: utf8.encode('Resumen de "$titulo"\n\n${frases.join('\n\n')}\n'),
      );
      if (context.mounted && path != null) _snack(context, 'Resumen descargado.');
    } catch (_) {
      if (context.mounted) _snack(context, 'No se pudo descargar el resumen.');
    }
    return;
  }
  _snack(context, 'Preparando el audio del resumen…');
  String? path;
  String? original;
  try {
    final dir = await getTemporaryDirectory();
    final base = '${dir.path}/Resumen_${DateTime.now().millisecondsSinceEpoch}';
    path = await handler.renderTextAudio(frases.join(' '), '$base.wav');
    if (path == null) throw AppException('Esta voz no permite guardar audio. Elige otra voz e inténtalo de nuevo.');
    if (Platform.isIOS) {
      final m4a = await const MethodChannel(
        'lector/audio_export',
      ).invokeMethod<String>('toM4a', {'path': path, 'out': '$base.m4a'});
      if (m4a != null && m4a.isNotEmpty) {
        original = path;
        path = m4a;
      }
    }
    if (!context.mounted) return;
    // La hoja Compartir ofrece "Guardar en Archivos", WhatsApp, etc.
    await const MethodChannel(
      'lector/share',
    ).invokeMethod<bool>('shareFile', {'path': path, 'text': 'Resumen de "$titulo" leído con PSSTH!'});
  } catch (error) {
    if (context.mounted) _snack(context, _say(error, 'No se pudo preparar el audio del resumen.'));
  } finally {
    for (final p in [path, original]) {
      if (p == null) continue;
      try {
        await File(p).delete();
      } catch (_) {}
    }
  }
}

/// "Compartir fragmento en audio": sintetiza la frase o la página actual con
/// la voz activa y la ofrece por la hoja Compartir (WhatsApp, Mensajes…).
/// Todo local: el audio se genera en el dispositivo y se borra al terminar.
Future<void> showShareAudioSheet(BuildContext context, TtsAudioHandler handler, LibraryEntry entry) async {
  if (handler.shareText().isEmpty) {
    _snack(context, 'No hay texto para compartir.');
    return;
  }
  final wholePage = await showSwarmSheet<bool>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('Compartir como nota de voz')),
          ListTile(
            leading: const Icon(CupertinoIcons.text_alignleft),
            title: const Text('La frase actual'),
            onTap: () => Navigator.pop(ctx, false),
          ),
          ListTile(
            leading: const Icon(CupertinoIcons.doc_text),
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
      final m4a = await const MethodChannel(
        'lector/audio_export',
      ).invokeMethod<String>('toM4a', {'path': path, 'out': '$base.m4a'});
      if (m4a != null && m4a.isNotEmpty) {
        original = path;
        path = m4a;
      }
    }
    if (!context.mounted) return;
    final dot = entry.name.lastIndexOf('.');
    final titulo = dot > 0 ? entry.name.substring(0, dot) : entry.name;
    await const MethodChannel(
      'lector/share',
    ).invokeMethod<bool>('shareFile', {'path': path, 'text': 'Fragmento de "$titulo" leído con PSSTH!'});
  } catch (error) {
    if (context.mounted) _snack(context, _say(error, 'No se pudo preparar el audio del fragmento.'));
  } finally {
    for (final p in [path, original]) {
      if (p == null) continue;
      try {
        await File(p).delete();
      } catch (_) {}
    }
  }
}
