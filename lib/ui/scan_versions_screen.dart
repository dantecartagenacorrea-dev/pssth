import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../domain/library_entry.dart';

/// Un PDF abierto, sin atar la pantalla al visor (las pruebas usan uno falso).
typedef ScanDocument = ({int pageCount, Widget Function(int index) page, Future<void> Function() close});
typedef ScanDocumentOpener = Future<ScanDocument> Function(String path);

IconData scanVersionIcon(ScanVersion version) => switch (version) {
  ScanVersion.original => CupertinoIcons.photo,
  ScanVersion.scanned => CupertinoIcons.doc,
  ScanVersion.clean => CupertinoIcons.doc_text,
};

Future<ScanDocument> _openFile(String path) async {
  if (!path.toLowerCase().endsWith('.pdf')) {
    return (
      pageCount: 1,
      close: () async {},
      page: (int _) => InteractiveViewer(
        maxScale: 4,
        child: Center(child: Image.file(File(path))),
      ),
    );
  }
  await pdfrxFlutterInitialize();
  final doc = await PdfDocument.openData(await File(path).readAsBytes(), sourceName: path);
  return (
    pageCount: doc.pages.length,
    close: doc.dispose,
    page: (int i) => InteractiveViewer(
      maxScale: 4,
      child: Center(
        child: AspectRatio(
          aspectRatio: doc.pages[i].width / doc.pages[i].height,
          child: ColoredBox(
            color: Colors.white,
            child: PdfPageView(document: doc, pageNumber: i + 1),
          ),
        ),
      ),
    ),
  );
}

/// Ver el original, el escaneado y la transcripción de una misma hoja.
class ScanVersionsScreen extends StatefulWidget {
  const ScanVersionsScreen({
    super.key,
    required this.entry,
    required this.initial,
    required this.prepare,
    this.initialPage = 0,
    this.open = _openFile,
  });

  final LibraryEntry entry;
  final ScanVersion initial;
  final int initialPage;
  final ScanDocumentOpener open;

  /// Dónde está esa vista; la arma si todavía no existe.
  final Future<String> Function(ScanVersion version) prepare;

  @override
  State<ScanVersionsScreen> createState() => _ScanVersionsScreenState();
}

class _ScanVersionsScreenState extends State<ScanVersionsScreen> {
  late ScanVersion _version = widget.initial;
  late int _page = widget.initialPage;
  late PageController _pages = PageController(initialPage: widget.initialPage);
  ScanDocument? _doc;
  bool _failed = false;
  bool _loading = true;

  /// Si se cambia de versión mientras otra abre, la vieja se descarta.
  int _opening = 0;

  /// Ruta de la vista en pantalla, la que se comparte.
  String? _path;

  @override
  void initState() {
    super.initState();
    _show(_version);
  }

  Future<void> _show(ScanVersion version) async {
    final ticket = ++_opening;
    setState(() {
      _version = version;
      _failed = false;
      _loading = true;
    });
    ScanDocument? opened;
    try {
      final path = await widget.prepare(version);
      if (!mounted || ticket != _opening) return;
      final doc = opened = await widget.open(path);
      if (!mounted || ticket != _opening) {
        await _close(doc);
        return;
      }
      if (doc.pageCount < 1) throw const FormatException('El PDF no tiene páginas.');
      final previous = _doc;
      final page = _page.clamp(0, doc.pageCount - 1);
      final old = _pages;
      setState(() {
        _doc = doc;
        _path = path;
        _loading = false;
        _page = page;
        _pages = PageController(initialPage: page);
      });
      // Después de reconstruir: la página anterior todavía los estaba usando.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        old.dispose();
        if (previous != null) _close(previous);
      });
    } catch (_) {
      // También sin memoria: mejor el aviso que quedarse cargando para siempre.
      if (opened != null) await _close(opened);
      if (mounted && ticket == _opening) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _close(ScanDocument doc) async {
    try {
      await doc.close();
    } on Exception {
      // Ya no se muestra: si no cierra bien no hay nada que avisar.
    }
  }

  Future<void> _share() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = Directory('${(await getTemporaryDirectory()).path}/escaneos');
      await dir.create(recursive: true);
      final name = widget.entry.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
      final path = _path!;
      final copy = await File(path).copy('${dir.path}/$name - ${_version.label}.${path.split('.').last}');
      await const MethodChannel('lector/share').invokeMethod<bool>('shareFile', {'path': copy.path});
    } on Exception {
      messenger.showSnackBar(const SnackBar(content: Text('No se pudo compartir esta versión.')));
    }
  }

  @override
  void dispose() {
    _opening++;
    _pages.dispose();
    final doc = _doc;
    if (doc != null) _close(doc);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return Scaffold(
      appBar: AppBar(
        title: Text(doc == null ? widget.entry.name : 'Página ${_page + 1} de ${doc.pageCount}'),
        actions: [
          IconButton(
            tooltip: 'Compartir esta versión',
            icon: const Icon(CupertinoIcons.share),
            // Solo lo que está a la vista: ni mientras carga otra ni si falló.
            onPressed: _loading || _failed ? null : _share,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final v in widget.entry.scanVersions)
                    ChoiceChip(
                      avatar: Icon(scanVersionIcon(v), size: 18),
                      label: Text(v.label),
                      selected: v == _version,
                      onSelected: v == _version ? null : (_) => _show(v),
                    ),
                ],
              ),
            ),
            Expanded(child: _content(doc)),
          ],
        ),
      ),
    );
  }

  Widget _content(ScanDocument? doc) {
    if (_failed) return const Center(child: Text('No se pudo abrir esta versión.'));
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Preparando esta vista…')],
        ),
      );
    }
    if (doc == null) return const SizedBox.shrink();
    return PageView.builder(
      key: ObjectKey(doc),
      controller: _pages,
      itemCount: doc.pageCount,
      onPageChanged: (i) => setState(() => _page = i),
      itemBuilder: (_, i) => doc.page(i),
    );
  }
}
