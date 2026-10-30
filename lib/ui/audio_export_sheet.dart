import 'dart:io' show Directory;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:path_provider/path_provider.dart';

import '../core/app_exception.dart';
import '../domain/chapter_detector.dart';
import '../domain/library_entry.dart';
import '../playback/range_audio_export.dart';
import '../playback/tts_audio_handler.dart';
import 'swarm_transition.dart';

void _snack(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: SwarmText(m)));

/// Páginas [from]..[to] (incluidas, desde 0) y cómo se llaman en el archivo.
typedef _Range = ({int from, int to, String label});

/// «Exportar en audio»: un capítulo, la página o un rango de páginas, leídos
/// con la voz activa en un solo archivo (.m4a) que se ofrece por la hoja
/// Compartir (Guardar en Archivos, Drive, WhatsApp…). Todo en el aparato.
Future<void> showAudioExportSheet(BuildContext context, TtsAudioHandler handler, LibraryEntry entry) async {
  final current = handler.currentChunk;
  if (current == null) {
    _snack(context, 'No hay texto para exportar.');
    return;
  }
  final lastPage = handler.chunks.last.pageIndex;
  final chapters = handler.chapters;
  final here = _chapterAt(chapters, current.pageIndex);
  final range = await showSwarmSheet<_Range>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(
            title: Text('Exportar en audio'),
            subtitle: Text('Con la voz actual. Tarda más o menos lo que dura el audio.'),
          ),
          if (here != null)
            ListTile(
              leading: const Icon(Icons.bookmark_outline),
              title: const Text('Este capítulo'),
              subtitle: Text(chapters[here].title, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () => Navigator.pop(ctx, _chapterRange(chapters, here, lastPage)),
            ),
          if (chapters.length > 1)
            ListTile(
              leading: const Icon(Icons.list),
              title: const Text('Otro capítulo…'),
              onTap: () async {
                final i = await _pickChapter(ctx, chapters);
                if (i != null && ctx.mounted) Navigator.pop(ctx, _chapterRange(chapters, i, lastPage));
              },
            ),
          ListTile(
            leading: const Icon(Icons.article_outlined),
            title: const Text('Esta página'),
            subtitle: Text('Página ${current.pageIndex + 1}'),
            onTap: () => Navigator.pop(ctx, (
              from: current.pageIndex,
              to: current.pageIndex,
              label: 'página ${current.pageIndex + 1}',
            )),
          ),
          ListTile(
            leading: const Icon(Icons.pages_outlined),
            title: const Text('Páginas…'),
            onTap: () async {
              final r = await _pickPages(ctx, current.pageIndex, lastPage);
              if (r != null && ctx.mounted) Navigator.pop(ctx, r);
            },
          ),
        ],
      ),
    ),
  );
  if (range == null || !context.mounted) return;
  await _run(context, handler, entry, range);
}

int? _chapterAt(List<Chapter> chapters, int page) {
  int? found;
  for (var i = 0; i < chapters.length; i++) {
    if (chapters[i].pageIndex <= page) found = i;
  }
  return found;
}

_Range _chapterRange(List<Chapter> chapters, int i, int lastPage) {
  final to = i + 1 < chapters.length ? chapters[i + 1].pageIndex - 1 : lastPage;
  return (from: chapters[i].pageIndex, to: to < chapters[i].pageIndex ? chapters[i].pageIndex : to, label: chapters[i].title);
}

Future<int?> _pickChapter(BuildContext context, List<Chapter> chapters) => showSwarmSheet<int>(
  context: context,
  isScrollControlled: true,
  builder: (ctx) => SafeArea(
    child: ListView(
      shrinkWrap: true,
      children: [
        for (var i = 0; i < chapters.length; i++)
          ListTile(
            title: Text(chapters[i].title),
            subtitle: Text('Página ${chapters[i].pageIndex + 1}'),
            onTap: () => Navigator.pop(ctx, i),
          ),
      ],
    ),
  ),
);

Future<_Range?> _pickPages(BuildContext context, int page, int lastPage) async {
  final from = TextEditingController(text: '${page + 1}');
  final to = TextEditingController(text: '${page + 1}');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('¿Qué páginas?'),
      content: Row(
        children: [
          Expanded(
            child: TextField(
              controller: from,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Desde'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: to,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'Hasta (máx. ${lastPage + 1})'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Exportar')),
      ],
    ),
  );
  final a = int.tryParse(from.text.trim());
  final b = int.tryParse(to.text.trim());
  from.dispose();
  to.dispose();
  if (ok != true || a == null || b == null) return null;
  final lo = (a < b ? a : b).clamp(1, lastPage + 1) - 1;
  final hi = (a < b ? b : a).clamp(1, lastPage + 1) - 1;
  return (from: lo, to: hi, label: lo == hi ? 'página ${lo + 1}' : 'páginas ${lo + 1}-${hi + 1}');
}

/// Arma el audio con avance y «Cancelar»; al terminar abre Compartir.
Future<void> _run(BuildContext context, TtsAudioHandler handler, LibraryEntry entry, _Range range) async {
  final sentences = handler.speechForPages(range.from, range.to);
  if (sentences.isEmpty) {
    _snack(context, 'Esas páginas no tienen texto para leer.');
    return;
  }
  final progress = ValueNotifier<double>(0);
  var cancelled = false;
  final dot = entry.name.lastIndexOf('.');
  final title = dot > 0 ? entry.name.substring(0, dot) : entry.name;
  final name = _safeName('$title - ${range.label}');
  final base = '${(await _exportDir()).path}/$name';
  if (!context.mounted) return;
  final dialog = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Preparando el audio'),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(range.label, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: v),
              const SizedBox(height: 8),
              // Al terminar de leer falta comprimirlo (no tiene avance propio).
              Text(v >= 1 ? 'Comprimiendo el audio…' : '${(v * 100).round()} %'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              Navigator.pop(ctx);
            },
            child: const Text('Cancelar'),
          ),
        ],
      ),
    ),
  );
  String? path;
  try {
    path = await exportSentencesAudio(
      sentences: sentences,
      base: base,
      render: handler.renderTextAudio,
      onProgress: (v) => progress.value = v,
      cancelled: () => cancelled,
    );
    if (!cancelled && context.mounted) Navigator.of(context, rootNavigator: true).pop();
    await dialog;
    if (path == null || cancelled || !context.mounted) return;
    await const MethodChannel(
      'lector/share',
    ).invokeMethod<bool>('shareFile', {'path': path, 'text': '"$title" (${range.label}) leído con PSSTH!'});
  } catch (error) {
    if (!cancelled && context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (context.mounted) {
      _snack(context, error is AppException ? error.message : 'No se pudo preparar el audio.');
    }
  } finally {
    progress.dispose();
  }
}

/// Carpeta temporal de los audios exportados. Se vacía al empezar otro: el
/// anterior no se borra enseguida porque la app que lo recibe (Drive,
/// WhatsApp…) lo sigue leyendo después de cerrar la hoja Compartir.
Future<Directory> _exportDir() async {
  final dir = Directory('${(await getTemporaryDirectory()).path}/audio_exportado');
  if (await dir.exists()) await dir.delete(recursive: true);
  return dir.create(recursive: true);
}

/// Nombre de archivo sin caracteres que los sistemas no aceptan.
String _safeName(String s) {
  final clean = s.replaceAll(RegExp(r'[\\/:*?"<>|·]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return clean.length > 80 ? clean.substring(0, 80).trim() : clean;
}
