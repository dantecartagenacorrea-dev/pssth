import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/text_chunk.dart';
import '../playback/tts_audio_handler.dart';
import 'swarm_transition.dart';

/// Rollo de lo ya leído: todo el texto desde el comienzo hasta la frase que
/// suena, en orden y por página, para repasarlo, seleccionar y copiar.
/// Se abre mostrando lo último leído.
Future<void> showReadScroll(BuildContext context, TtsAudioHandler handler) {
  final read = readSoFar(handler.chunks, handler.chunkIndex);
  return showSwarmSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (ctx, controller) => _ReadScroll(pages: read, controller: controller),
    ),
  );
}

/// Texto leído hasta [index] (incluido), agrupado por página: (número de
/// página desde 1, texto).
List<(int, String)> readSoFar(List<TextChunk> chunks, int index) {
  final pages = <(int, String)>[];
  final buffer = StringBuffer();
  int? page;
  var last = '';
  for (var i = 0; i <= index && i < chunks.length; i++) {
    final c = chunks[i];
    if (page != null && c.pageIndex != page) {
      pages.add((page + 1, buffer.toString()));
      buffer.clear();
    }
    page = c.pageIndex;
    final text = c.text.trim();
    if (text.isEmpty) continue;
    // Un fragmento sin puntuación al final (título, elemento de lista) va en
    // su propia línea; las frases de un mismo párrafo siguen en la misma.
    if (buffer.isNotEmpty) buffer.write(_endsSentence.hasMatch(last) ? ' ' : '\n');
    buffer.write(text);
    last = text;
  }
  if (page != null) pages.add((page + 1, buffer.toString()));
  return pages;
}

final _endsSentence = RegExp(r'[.,;:!?…»)"]\s*$');

class _ReadScroll extends StatefulWidget {
  const _ReadScroll({required this.pages, required this.controller});
  final List<(int, String)> pages;
  final ScrollController controller;

  @override
  State<_ReadScroll> createState() => _ReadScrollState();
}

class _ReadScrollState extends State<_ReadScroll> {
  @override
  void initState() {
    super.initState();
    // Abre al final: lo último que se leyó queda a la vista.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = widget.controller;
      if (c.hasClients) c.jumpTo(c.position.maxScrollExtent);
    });
  }

  Future<void> _copyAll() async {
    final all = widget.pages.map((p) => p.$2).join('\n\n');
    await Clipboard.setData(ClipboardData(text: all));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: SwarmText('Texto leído copiado.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gray = theme.colorScheme.secondary;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
          child: Row(
            children: [
              Expanded(child: Text('Lo que ya leíste', style: theme.textTheme.titleMedium)),
              TextButton.icon(
                onPressed: widget.pages.isEmpty ? null : _copyAll,
                icon: const Icon(Icons.copy_all_rounded),
                label: const Text('Copiar todo'),
              ),
            ],
          ),
        ),
        Expanded(
          child: widget.pages.isEmpty
              ? Center(
                  child: Text('Todavía no se leyó nada.', style: TextStyle(color: gray)),
                )
              // Una sola zona de selección: se puede marcar de una página a otra.
              : SelectionArea(
                  child: ListView.builder(
                    controller: widget.controller,
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    itemCount: widget.pages.length,
                    itemBuilder: (context, i) {
                      final (page, text) = widget.pages[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Página $page', style: theme.textTheme.labelSmall),
                            const SizedBox(height: 6),
                            Text(text, style: theme.textTheme.bodyLarge?.copyWith(height: 1.55)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}
