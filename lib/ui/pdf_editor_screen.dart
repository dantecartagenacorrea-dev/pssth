import 'dart:io' show Directory, File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/pdf_editor.dart';
import 'swarm_transition.dart';
import 'premium.dart';

void _snack(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: SwarmText(m)));

/// Herramientas para marcar la página.
enum _Tool {
  highlight('Resaltar', CupertinoIcons.paintbrush),
  pen('Lápiz', CupertinoIcons.scribble),
  note('Nota', CupertinoIcons.doc_plaintext),
  text('Texto', CupertinoIcons.textformat),
  correct('Corregir', CupertinoIcons.square_pencil),
  sign('Firma', CupertinoIcons.signature);

  const _Tool(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// «Editar PDF»: organizar páginas, anotar y corregir texto sobre una copia.
/// El archivo original no cambia; al final se guarda o se comparte el nuevo.
class PdfEditorScreen extends StatefulWidget {
  const PdfEditorScreen({super.key, required this.path, required this.title});
  final String path;
  final String title;

  @override
  State<PdfEditorScreen> createState() => _PdfEditorScreenState();
}

class _PdfEditorScreenState extends State<PdfEditorScreen> {
  PdfEditor? _ed;
  String? _error;
  bool _busy = false;
  bool _pagesMode = true;
  int _page = 0;
  _Tool _tool = _Tool.highlight;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      await pdfrxFlutterInitialize();
      final ed = await PdfEditor.openFile(widget.path);
      if (!mounted) {
        await ed.dispose();
        return;
      }
      if (ed.locked) {
        await ed.dispose();
        if (mounted) {
          setState(() => _error = 'Este PDF está protegido por su autor: se puede leer y escuchar, pero no editar.');
        }
        return;
      }
      ed.changes.addListener(_refresh);
      setState(() => _ed = ed);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo abrir el PDF para editarlo: está protegido con contraseña o dañado.');
      }
    }
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _page = _page.clamp(0, (_ed?.pageCount ?? 1) - 1));
  }

  @override
  void dispose() {
    _ed?.changes.removeListener(_refresh);
    _ed?.dispose();
    super.dispose();
  }

  /// Corre un cambio con la pantalla en espera; un fallo se avisa sin cerrar.
  Future<void> _do(Future<void> Function(PdfEditor ed) change) async {
    final ed = _ed;
    if (ed == null || _busy) return;
    setState(() => _busy = true);
    try {
      await change(ed);
    } catch (_) {
      if (mounted) _snack(context, 'No se pudo hacer ese cambio en este PDF.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _baseName {
    final dot = widget.title.lastIndexOf('.');
    return dot > 0 ? widget.title.substring(0, dot) : widget.title;
  }

  Future<void> _save() async {
    final ed = _ed;
    if (ed == null) return;
    final share = await showSwarmSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text('Guardar el PDF editado'),
              subtitle: Text('Es una copia: el original no cambia.'),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.arrow_down_doc),
              title: const Text('Guardar en el dispositivo'),
              onTap: () => Navigator.pop(ctx, false),
            ),
            ListTile(
              leading: const Icon(CupertinoIcons.share),
              title: const Text('Compartir'),
              onTap: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );
    if (share == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final bytes = await ed.save();
      final name = '$_baseName (editado).pdf';
      if (share) {
        final file = File('${(await getTemporaryDirectory()).path}/$name');
        await file.writeAsBytes(bytes, flush: true);
        await const MethodChannel('lector/share').invokeMethod<bool>('shareFile', {'path': file.path});
      } else {
        final path = await FilePicker.platform.saveFile(dialogTitle: 'Guardar PDF', fileName: name, bytes: bytes);
        if (path != null && mounted) _snack(context, 'PDF guardado.');
      }
      _saved = ed.changes.value;
    } catch (_) {
      if (mounted) _snack(context, 'No se pudo guardar el PDF.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Cambios ya guardados (para no preguntar al salir).
  int _saved = 0;

  Future<bool> _confirmLeave() async {
    final ed = _ed;
    if (ed == null || ed.changes.value == _saved) return true;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Salir sin guardar?'),
        content: const Text('Los cambios de este PDF se pierden. El original sigue igual.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Seguir editando')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salir')),
        ],
      ),
    );
    return leave ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final ed = _ed;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) Navigator.pop(context);
      },
      child: PremiumPage(
        title: 'Editar PDF',
        subtitle: widget.title,
        actions: [
          PageAction(
            icon: CupertinoIcons.arrow_uturn_left,
            tooltip: 'Deshacer',
            onTap: ed == null || !ed.canUndo || _busy ? null : () => _do((e) => e.undo()),
          ),
          PageAction(
            icon: CupertinoIcons.floppy_disk,
            tooltip: 'Guardar copia',
            onTap: ed == null || _busy ? null : _save,
            primary: true,
          ),
        ],
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: SafeArea(top: false, child: _body(context, ed))),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, PdfEditor? ed) {
    if (_error case final error?) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.lock, size: 40),
              const SizedBox(height: 12),
              Text(error, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    if (ed == null) return const Center(child: CircularProgressIndicator());
    return Column(
      children: [
        if (ed.signed)
          const MaterialBanner(
            content: Text(
              'Este PDF tiene firma digital: la copia editada ya no la tendrá válida. El original no cambia.',
            ),
            actions: [SizedBox.shrink()],
          ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Páginas'), icon: Icon(CupertinoIcons.square_grid_2x2)),
              ButtonSegment(value: false, label: Text('Anotar y corregir'), icon: Icon(CupertinoIcons.pencil)),
            ],
            selected: {_pagesMode},
            onSelectionChanged: (v) => setState(() => _pagesMode = v.first),
          ),
        ),
        Expanded(child: _pagesMode ? _pagesGrid(context, ed) : _annotate(context, ed)),
      ],
    );
  }

  // ---------- Páginas ----------

  /// Páginas elegidas (mantener presionada una para empezar a elegir).
  final Set<int> _selected = {};

  Widget _pagesGrid(BuildContext context, PdfEditor ed) {
    final n = ed.pageCount;
    final s = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: _selected.isEmpty ? _pagesBar(ed) : _selectionBar(ed),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              childAspectRatio: 0.62,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: n,
            itemBuilder: (context, i) {
              final chosen = _selected.contains(i);
              return Card(
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: BorderSide(color: chosen ? s.onSurface : Colors.transparent, width: 2.5),
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: InkWell(
                        // Eligiendo: tocar suma o saca la página. Si no, abre
                        // la página para anotarla.
                        onTap: () => setState(() {
                          if (_selected.isNotEmpty) {
                            chosen ? _selected.remove(i) : _selected.add(i);
                          } else {
                            _page = i;
                            _pagesMode = false;
                          }
                        }),
                        onLongPress: () => setState(() => chosen ? _selected.remove(i) : _selected.add(i)),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            PdfPageView(
                              key: ValueKey('${ed.changes.value}-$i'),
                              document: ed.doc,
                              pageNumber: i + 1,
                              maximumDpi: 40,
                            ),
                            if (chosen)
                              Align(
                                alignment: Alignment.topRight,
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Icon(CupertinoIcons.checkmark_circle_fill, color: s.onSurface, size: 26),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    Text('${i + 1}', style: Theme.of(context).textTheme.labelSmall),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _mini('Girar', CupertinoIcons.rotate_right, () => _do((e) => e.rotate(i))),
                        _mini(
                          'Antes',
                          CupertinoIcons.chevron_left,
                          i == 0 ? null : () => _do((e) => e.movePage(i, i - 1)),
                        ),
                        _mini(
                          'Después',
                          CupertinoIcons.chevron_right,
                          i == n - 1 ? null : () => _do((e) => e.movePage(i, i + 1)),
                        ),
                        _mini('Quitar', CupertinoIcons.trash, n <= 1 ? null : () => _do((e) => e.removePage(i))),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Sin páginas elegidas: agregar otro PDF y, si hay algo copiado, pegarlo.
  Widget _pagesBar(PdfEditor ed) => ValueListenableBuilder<PageClip?>(
    valueListenable: PageClip.current,
    builder: (context, clip, _) => Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OutlinedButton.icon(
          icon: const Icon(CupertinoIcons.plus_square_on_square, size: 18),
          label: const Text('Agregar otro PDF'),
          onPressed: _busy ? null : _appendPdf,
        ),
        if (clip != null)
          FilledButton.icon(
            icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 18),
            label: Text(
              clip.pages.length == 1 ? 'Pegar 1 página al final' : 'Pegar ${clip.pages.length} páginas al final',
            ),
            onPressed: _busy ? null : () => _do((e) => e.pastePages(clip)),
          ),
        Text('Mantén presionada una página para elegir varias.', style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );

  /// Con páginas elegidas: lo que se puede hacer con ellas.
  Widget _selectionBar(PdfEditor ed) {
    final pages = (_selected.toList()..sort());
    final n = pages.length;
    Future<void> act(Future<void> Function(PdfEditor e, Directory tmp) f, String done) async {
      final tmp = await getTemporaryDirectory();
      await _do((e) => f(e, tmp));
      if (!mounted) return;
      setState(_selected.clear);
      _snack(context, done);
    }

    return ValueListenableBuilder<PageClip?>(
      valueListenable: PageClip.current,
      builder: (context, clip, _) => Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(n == 1 ? '1 página' : '$n páginas', style: Theme.of(context).textTheme.titleSmall),
          OutlinedButton.icon(
            icon: const Icon(CupertinoIcons.doc_on_doc, size: 18),
            label: const Text('Copiar'),
            onPressed: _busy
                ? null
                : () => act((e, t) => e.copyPages(pages, t), 'Copiadas: puedes pegarlas aquí o en otro PDF.'),
          ),
          OutlinedButton.icon(
            icon: const Icon(CupertinoIcons.scissors, size: 18),
            label: const Text('Cortar'),
            onPressed: _busy || n >= ed.pageCount
                ? null
                : () => act((e, t) => e.cutPages(pages, t), 'Cortadas: puedes pegarlas aquí o en otro PDF.'),
          ),
          if (clip != null)
            OutlinedButton.icon(
              icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 18),
              label: const Text('Pegar antes'),
              onPressed: _busy ? null : () => act((e, _) => e.pastePages(clip, at: pages.first), 'Páginas pegadas.'),
            ),
          OutlinedButton.icon(
            icon: const Icon(CupertinoIcons.rotate_right, size: 18),
            label: const Text('Girar'),
            onPressed: _busy ? null : () => act((e, _) => e.rotatePages(pages), 'Páginas giradas.'),
          ),
          OutlinedButton.icon(
            icon: const Icon(CupertinoIcons.trash, size: 18),
            label: const Text('Quitar'),
            onPressed: _busy || n >= ed.pageCount
                ? null
                : () => act((e, _) => e.removePages(pages), 'Páginas quitadas.'),
          ),
          IconButton(
            tooltip: 'Dejar de elegir',
            icon: const Icon(CupertinoIcons.xmark),
            onPressed: () => setState(_selected.clear),
          ),
        ],
      ),
    );
  }

  Widget _mini(String tip, IconData icon, VoidCallback? onTap) => IconButton(
    tooltip: tip,
    visualDensity: VisualDensity.compact,
    iconSize: 20,
    icon: Icon(icon),
    onPressed: _busy ? null : onTap,
  );

  Future<void> _appendPdf() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final path = picked?.files.single.path;
    if (path == null) return;
    await _do((e) => e.appendFile(path));
  }

  // ---------- Anotar y corregir ----------

  Widget _annotate(BuildContext context, PdfEditor ed) {
    final page = ed.doc.pages[_page];
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              for (final t in _Tool.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    avatar: Icon(t.icon, size: 18),
                    label: Text(t.label),
                    selected: _tool == t,
                    onSelected: (_) => setState(() => _tool = t),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(6),
          child: Text(_hint, textAlign: TextAlign.center),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final scale = [box.maxWidth / page.width, box.maxHeight / page.height].reduce((a, b) => a < b ? a : b);
              final size = Size(page.width * scale, page.height * scale);
              return Center(
                child: SizedBox.fromSize(
                  size: size,
                  child: _PageCanvas(
                    key: ValueKey('${ed.changes.value}-$_page'),
                    document: ed.doc,
                    pageNumber: _page + 1,
                    tool: _tool,
                    enabled: !_busy,
                    onRect: (r) => _onRect(ed, r),
                    onStroke: (s) => _do((e) => e.ink(_page, [s])),
                    onTap: (p) => _onTap(ed, p, page.width / page.height),
                  ),
                ),
              );
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              tooltip: 'Página anterior',
              icon: const Icon(CupertinoIcons.chevron_left),
              onPressed: _page == 0 ? null : () => setState(() => _page--),
            ),
            Text('Página ${_page + 1} de ${ed.pageCount}'),
            IconButton(
              tooltip: 'Página siguiente',
              icon: const Icon(CupertinoIcons.chevron_right),
              onPressed: _page >= ed.pageCount - 1 ? null : () => setState(() => _page++),
            ),
          ],
        ),
      ],
    );
  }

  String get _hint => switch (_tool) {
    _Tool.highlight => 'Arrastra sobre lo que quieres resaltar.',
    _Tool.pen => 'Dibuja con el dedo.',
    _Tool.note => 'Toca donde va la nota.',
    _Tool.text => 'Toca donde empieza el texto.',
    _Tool.correct => 'Arrastra sobre la palabra a corregir: se tapa y escribes encima.',
    _Tool.sign => 'Toca donde va la firma.',
  };

  Future<void> _onRect(PdfEditor ed, Rect r) async {
    if (_tool == _Tool.highlight) return _do((e) => e.highlight(_page, r));
    final text = await _ask('Texto correcto', hint: 'Lo que debe decir (vacío: solo tapar)');
    if (text == null) return;
    await _do((e) => e.correct(_page, r, text));
  }

  Future<void> _onTap(PdfEditor ed, Offset at, double aspect) async {
    switch (_tool) {
      case _Tool.note:
        final text = await _ask('Nota', hint: 'Escribe la nota');
        if (text != null && text.trim().isNotEmpty) await _do((e) => e.note(_page, at, text.trim()));
      case _Tool.text:
        final result = await _askText();
        if (result != null) await _do((e) => e.addText(_page, at, result.text, size: result.size));
      case _Tool.sign:
        final strokes = await showDialog<List<List<Offset>>>(context: context, builder: (_) => const _SignaturePad());
        if (strokes == null || strokes.isEmpty) return;
        // Firma de un tercio del ancho, con la forma del recuadro (3 × 1).
        const w = 0.33;
        final h = w * aspect / 3;
        final placed = [
          for (final s in strokes) [for (final p in s) Offset(at.dx + (p.dx - 0.5) * w, at.dy + (p.dy - 0.5) * h)],
        ];
        await _do((e) => e.ink(_page, placed, color: kTextBlack, width: 1.4));
      default:
    }
  }

  Future<String?> _ask(String title, {String hint = ''}) async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLines: 4,
          minLines: 1,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Listo')),
        ],
      ),
    );
    c.dispose();
    return r;
  }

  Future<({String text, double size})?> _askText() async {
    final c = TextEditingController();
    var size = 14.0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Agregar texto'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: c, autofocus: true, maxLines: 5, minLines: 1),
              const SizedBox(height: 12),
              SegmentedButton<double>(
                segments: const [
                  ButtonSegment(value: 10, label: Text('Chico')),
                  ButtonSegment(value: 14, label: Text('Normal')),
                  ButtonSegment(value: 22, label: Text('Grande')),
                ],
                selected: {size},
                onSelectionChanged: (v) => set(() => size = v.first),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Agregar')),
          ],
        ),
      ),
    );
    final text = c.text.trim();
    c.dispose();
    return ok == true && text.isNotEmpty ? (text: text, size: size) : null;
  }
}

/// La página con lo que se va dibujando encima (área o trazo). Las posiciones
/// salen normalizadas (0–1) sobre la página como se ve.
class _PageCanvas extends StatefulWidget {
  const _PageCanvas({
    super.key,
    required this.document,
    required this.pageNumber,
    required this.tool,
    required this.enabled,
    required this.onRect,
    required this.onStroke,
    required this.onTap,
  });
  final PdfDocument document;
  final int pageNumber;
  final _Tool tool;
  final bool enabled;
  final ValueChanged<Rect> onRect;
  final ValueChanged<List<Offset>> onStroke;
  final ValueChanged<Offset> onTap;

  @override
  State<_PageCanvas> createState() => _PageCanvasState();
}

class _PageCanvasState extends State<_PageCanvas> {
  Offset? _start, _end;
  List<Offset> _stroke = [];

  bool get _dragsArea => widget.tool == _Tool.highlight || widget.tool == _Tool.correct;

  Offset _norm(Offset local, Size size) =>
      Offset((local.dx / size.width).clamp(0.0, 1.0), (local.dy / size.height).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final size = box.biggest;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: widget.enabled && !_dragsArea && widget.tool != _Tool.pen
            ? (d) => widget.onTap(_norm(d.localPosition, size))
            : null,
        onPanStart: widget.enabled && (_dragsArea || widget.tool == _Tool.pen)
            ? (d) => setState(() {
                _start = _end = _norm(d.localPosition, size);
                _stroke = [_start!];
              })
            : null,
        onPanUpdate: (d) => setState(() {
          _end = _norm(d.localPosition, size);
          _stroke.add(_end!);
        }),
        onPanEnd: (_) {
          final s = _start, e = _end;
          setState(() => _start = _end = null);
          if (s == null || e == null) return;
          if (widget.tool == _Tool.pen) {
            widget.onStroke(List.of(_stroke));
          } else {
            final r = Rect.fromPoints(s, e);
            if (r.width > 0.005 && r.height > 0.005) widget.onRect(r);
          }
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Colors.white,
              child: PdfPageView(document: widget.document, pageNumber: widget.pageNumber),
            ),
            CustomPaint(painter: _Draft(_start, _end, widget.tool == _Tool.pen ? _stroke : const [], widget.tool)),
          ],
        ),
      );
    },
  );
}

/// Lo que se está marcando, antes de soltar el dedo.
class _Draft extends CustomPainter {
  _Draft(this.start, this.end, this.stroke, this.tool);
  final Offset? start, end;
  final List<Offset> stroke;
  final _Tool tool;

  @override
  void paint(Canvas canvas, Size size) {
    Offset px(Offset n) => Offset(n.dx * size.width, n.dy * size.height);
    if (stroke.length > 1 && start != null) {
      final path = Path()..moveTo(px(stroke.first).dx, px(stroke.first).dy);
      for (final p in stroke.skip(1)) {
        path.lineTo(px(p).dx, px(p).dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF143CC8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
      return;
    }
    if (start == null || end == null) return;
    final r = Rect.fromPoints(px(start!), px(end!));
    canvas.drawRect(r, Paint()..color = tool == _Tool.correct ? const Color(0x55FFFFFF) : const Color(0x66FFD600));
    canvas.drawRect(
      r,
      Paint()
        ..color = const Color(0xFF888888)
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_Draft old) => true;
}

/// Recuadro (3 × 1) para firmar con el dedo. Devuelve los trazos
/// normalizados al recuadro.
class _SignaturePad extends StatefulWidget {
  const _SignaturePad();

  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  final List<List<Offset>> _strokes = [];

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Firma'),
    content: SizedBox(
      width: 360,
      child: AspectRatio(
        aspectRatio: 3,
        child: LayoutBuilder(
          builder: (context, box) {
            final size = box.biggest;
            Offset norm(Offset p) => Offset((p.dx / size.width).clamp(0.0, 1.0), (p.dy / size.height).clamp(0.0, 1.0));
            return GestureDetector(
              onPanStart: (d) => setState(() => _strokes.add([norm(d.localPosition)])),
              onPanUpdate: (d) => setState(() => _strokes.last.add(norm(d.localPosition))),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey),
                ),
                child: CustomPaint(painter: _Strokes(_strokes), size: size),
              ),
            );
          },
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => setState(_strokes.clear), child: const Text('Borrar')),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      FilledButton(onPressed: () => Navigator.pop(context, _strokes), child: const Text('Usar firma')),
    ],
  );
}

class _Strokes extends CustomPainter {
  _Strokes(this.strokes);
  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    for (final s in strokes) {
      if (s.length < 2) continue;
      final path = Path()..moveTo(s.first.dx * size.width, s.first.dy * size.height);
      for (final p in s.skip(1)) {
        path.lineTo(p.dx * size.width, p.dy * size.height);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_Strokes old) => true;
}
