import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../data/scan_options_store.dart';
import '../domain/read_lines_align.dart';
import '../domain/retype_ink.dart';
import '../domain/scan_filters.dart';
import '../domain/scanned_pdf.dart';
import '../domain/spanish_words.dart';
import 'retype_editor.dart';
import 'premium.dart';

/// Página limpia lista para el PDF.
typedef CleanPage = ({Uint8List jpeg, int width, int height});

/// Lo que se decidió al revisar: las fotos que quedaron, en orden, sus páginas
/// limpias y, si se pidió «Transcribir», los renglones ya comparados de cada una,
/// con sus negritas y las firmas y sellos que van.
typedef ScanReview = ({
  List<String> paths,
  List<CleanPage> pages,
  List<List<ScannedLine>>? retyped,
  List<PageInk>? ink,
  ScanOptions options,
  List<List<PageMark>>? removedMarks,
});

/// Revisión de lo escaneado: se giran, ordenan o quitan páginas, se elige cómo
/// limpiarlas viendo cómo queda, o «Transcribir» para reescribirlas, y se confirma. Devuelve la revisión, en orden, o null si se cancela.
class ScanReviewScreen extends StatefulWidget {
  const ScanReviewScreen({
    super.key,
    required this.paths,
    required this.recognize,
    this.readWithAi,
    this.loadWords,
    this.addPages,
    this.transcribe = false,
    this.options = defaultScanOptions,
  });

  /// Con qué opciones de PDF se empieza.
  final ScanOptions options;

  /// Escanea más páginas y devuelve sus fotos; vacío si se canceló. Sin esto
  /// no se ofrece agregar.
  final Future<List<String>> Function()? addPages;

  final List<String> paths;

  /// Abre ya en «Transcribir» y lee todas las páginas de una vez, sin esperar
  /// a que se miren una por una.
  final bool transcribe;

  /// Lee los renglones de una foto.
  final Future<List<ScannedLine>> Function(String path) recognize;

  /// Lee la foto con la IA de la computadora; null si no se pudo. Sin esto se usa
  /// solo el lector común.
  final Future<String?> Function(String path)? readWithAi;

  /// El diccionario con que se revisa lo leído sin IA.
  final Future<SpanishWords> Function()? loadWords;

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  // Lo que entregó el escáner, sin tocar: ningún filtro se aplica por su cuenta.
  ScanFilter _filter = ScanFilter.original;
  bool _retype = false;
  int _page = 0;
  bool _finishing = false;
  bool _rotating = false;
  bool _adding = false;
  late ScanPaper _paper = widget.options.paper;
  late ScanQuality _quality = widget.options.quality;
  late bool _keepForm = widget.options.keepForm;
  static const _thumbCacheHeight = 112;
  late final List<String> _paths = [...widget.paths];
  final _pager = PageController();

  @override
  void initState() {
    super.initState();
    if (widget.transcribe) _startRetype();
  }

  /// Pasa a «Transcribir» y lee todas las páginas, de a una para no saturar la IA.
  void _startRetype() {
    _retype = true;
    unawaited(_readAll());
  }

  Future<void> _readAll() async {
    for (final path in [..._paths]) {
      if (!mounted || !_retype) return;
      try {
        await _lines(path);
      } on Exception {
        // La página muestra su propio error al verla; las demás siguen.
      }
    }
  }

  /// Filtro propio de cada página, si se eligió «Solo esta página».
  final _ownFilter = <String, ScanFilter>{};
  bool _onlyThisPage = false;
  ScanFilter _filterOf(String path) => _ownFilter[path] ?? _filter;

  void _choose(ScanFilter f) => setState(() {
    _retype = false;
    if (_onlyThisPage) {
      _ownFilter[_paths[_page]] = f;
    } else {
      _filter = f;
      _ownFilter.clear();
    }
  });

  final _sharpness = <String, Future<double>>{};
  Future<double> _sharpnessOf(String path) => _sharpness.putIfAbsent(path, () => scanSharpness(path));

  /// Sube al girar una página: su miniatura tiene que volver a leerse.
  final _versions = <String, int>{};

  /// Páginas ya limpias, por filtro: cambiar de filtro y volver es instantáneo.
  final _done = <(ScanFilter, String), Future<CleanPage>>{};
  final _originals = <String, Future<Uint8List>>{};

  Future<CleanPage> _clean(String path, ScanFilter filter) => _done.putIfAbsent((filter, path), () async {
    final jpeg = await _originals.putIfAbsent(path, () => File(path).readAsBytes());
    return applyScanFilter(jpeg, filter);
  });

  final _usableCache = <(ScanFilter, String), Future<bool>>{};

  /// Si [filter] conserva la hoja entera. Se mide en la página de verdad, no
  /// en la miniatura: achicada, una trama se esfuma y el filtro parecería inocente.
  Future<bool> _usable(String path, ScanFilter filter) {
    if (filter == ScanFilter.original) return Future.value(true);
    return _usableCache.putIfAbsent((filter, path), () async {
      try {
        final photo = await _originals.putIfAbsent(path, () => File(path).readAsBytes());
        final page = await _clean(path, filter);
        return await contentKept(photo, page.jpeg) >= minContentKept;
      } catch (_) {
        return false; // si no se pudo aplicar, tampoco se ofrece
      }
    });
  }

  /// El filtro que de verdad lleva la página: el elegido, si no borra nada.
  Future<ScanFilter> _effectiveFilter(String path) async {
    final chosen = _filterOf(path);
    return await _usable(path, chosen) ? chosen : ScanFilter.original;
  }

  final _shown = <(ScanFilter, String), Future<CleanPage>>{};

  Future<CleanPage> _shownPage(String path) =>
      _shown.putIfAbsent((_filterOf(path), path), () async => _clean(path, await _effectiveFilter(path)));

  /// Miniaturas: cada filtro aplicado a una copia chica, para compararlos rápido.
  final _thumbBase = <String, Future<Uint8List>>{};
  final _thumbs = <(ScanFilter, String), Future<CleanPage>>{};

  Future<CleanPage> _thumb(String path, ScanFilter filter) => _thumbs.putIfAbsent((
    filter,
    path,
  ), () async => applyScanFilter(await _thumbBase.putIfAbsent(path, () => scanThumbnail(path)), filter));

  /// Lo leído en cada página, de arriba abajo, y cómo va quedando corregido.
  final _read = <String, Future<List<ScannedLine>>>{};
  final _edits = <String, List<TextEditingController>>{};
  final _compare = <String, Future<List<Object>>>{};
  final _doubts = <String, Set<int>>{};
  final _readByAi = <String>{};
  final _ink = <String, PageInk>{};

  /// Lo que no es firma ni sello y se pidió sacar, por página.
  final _hiddenMarks = <String, Set<int>>{};

  Future<List<ScannedLine>> _lines(String path) => _read.putIfAbsent(path, () async {
    // Lo de un sello no es parte del texto.
    final version = _versions[path] ?? 0;
    var lines = [...await widget.recognize(path)]..sort((a, b) => a.top.compareTo(b.top));
    var guessed = const <int>{};
    var read = const <int>{};
    var byAi = false;
    final aiText = await widget.readWithAi?.call(path);
    final aiLines = aiText == null ? const <String>[] : linesFromAiText(aiText);
    if (aiLines.isNotEmpty) {
      final aligned = alignReadLines(aiLines, lines);
      lines = aligned.lines;
      read = aligned.doubts;
      guessed = aligned.guessed;
      byAi = true;
    } else {
      // Sin diccionario la hoja sale igual, solo que sin revisar.
      final words = await widget.loadWords?.call().then<SpanishWords?>((w) => w).catchError((Object _) => null);
      if (words != null) {
        final checked = checkSpelling(lines, words);
        lines = checked.lines;
        read = checked.doubts;
      }
    }
    // Un renglón de lugar estimado no puede reclamar la tinta que le caiga encima.
    final placed = [
      for (final (i, l) in lines.indexed)
        guessed.contains(i) ? (text: l.text, left: l.left, top: l.top, width: 0.0, height: 0.0) : l,
    ];
    // Sin esto la hoja sale igual, solo que sin negritas ni firmas.
    final ink = await readInk(path, placed).catchError((Object _) => noInk);
    // Si se giró la página mientras tanto, esta lectura ya no vale.
    if (!mounted || (_versions[path] ?? 0) != version) return lines;
    if (byAi) _readByAi.add(path);
    // Lo de un sello va en su recorte, no en el texto.
    final kept = [
      for (var i = 0; i < lines.length; i++)
        if (!ink.stamps.contains(i)) i,
    ];
    _doubts[path] = {
      for (final (now, i) in kept.indexed)
        if (read.contains(i)) now,
    };
    _ink[path] = (
      bold: [
        for (final i in kept)
          if (i < ink.bold.length) ink.bold[i],
      ],
      marks: ink.marks,
      stamps: const <int>{},
    );
    lines = [for (final i in kept) lines[i]];
    _edits[path] = [for (final l in lines) TextEditingController(text: l.text)];
    return lines;
  });

  Future<List<ScannedLine>> _edited(String path) async {
    final lines = await _lines(path);
    final edits = _edits[path]!;
    return [
      for (var i = 0; i < lines.length; i++)
        (text: edits[i].text, left: lines[i].left, top: lines[i].top, width: lines[i].width, height: lines[i].height),
    ];
  }

  /// Las negritas al día con lo corregido, y solo las firmas y sellos que quedaron.
  Future<PageInk> _finalInk(String path) async {
    final lines = await _lines(path);
    final edits = _edits[path]!;
    final ink = _ink[path] ?? noInk;
    final hidden = _hiddenMarks[path] ?? const <int>{};
    return (
      bold: [
        for (var i = 0; i < lines.length; i++)
          boldAfterEdit(lines[i].text, edits[i].text, i < ink.bold.length ? ink.bold[i] : null),
      ],
      marks: [
        for (final (i, mark) in ink.marks.indexed)
          if (!hidden.contains(i)) mark,
      ],
      stamps: const <int>{},
    );
  }

  Future<void> _rotate() async {
    final path = _paths[_page];
    setState(() => _rotating = true);
    try {
      await rotateScanFile(path);
      await ResizeImage(FileImage(File(path)), height: _thumbCacheHeight).evict();
      if (!mounted) return;
      // Lo leído y lo limpiado eran de la foto sin girar.
      setState(() {
        _done.removeWhere((key, _) => key.$2 == path);
        _usableCache.removeWhere((key, _) => key.$2 == path);
        _shown.removeWhere((key, _) => key.$2 == path);
        _thumbs.removeWhere((key, _) => key.$2 == path);
        _thumbBase.remove(path);
        _sharpness.remove(path);
        _originals.remove(path);
        _read.remove(path);
        _compare.remove(path);
        _doubts.remove(path);
        _readByAi.remove(path);
        _ink.remove(path);
        _hiddenMarks.remove(path);
        for (final edit in _edits.remove(path) ?? const <TextEditingController>[]) {
          edit.dispose();
        }
        _versions[path] = (_versions[path] ?? 0) + 1;
      });
    } on FileSystemException {
      _sayFailed();
    } on FormatException {
      _sayFailed();
    } finally {
      if (mounted) setState(() => _rotating = false);
    }
  }

  /// Las páginas nuevas van al final y se muestra la primera de ellas.
  Future<void> _addPages() async {
    setState(() => _adding = true);
    try {
      final more = await widget.addPages!();
      if (!mounted || more.isEmpty) return;
      final first = _paths.length;
      setState(() => _paths.addAll(more));
      if (_retype) unawaited(_readAll());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pager.hasClients) _pager.jumpToPage(first);
      });
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  List<PageMark> _removedMarks(String path) {
    final hidden = _hiddenMarks[path] ?? const <int>{};
    return [
      for (final (i, mark) in (_ink[path]?.marks ?? const <PageMark>[]).indexed)
        if (hidden.contains(i)) mark,
    ];
  }

  /// Copia lo leído de todas las páginas, con lo que ya se haya corregido.
  Future<void> _copyText() async {
    try {
      final pages = [
        for (final path in [..._paths]) (await _edited(path)).map((l) => l.text).join('\n'),
      ];
      await Clipboard.setData(ClipboardData(text: pages.join('\n\n')));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Texto copiado.')));
    } catch (_) {
      // También si la página se giró mientras se leía.
      _sayFailed();
    }
  }

  /// Tamaño de hoja y peso del PDF.
  void _showPdfOptions() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          void update(VoidCallback change) {
            setState(change);
            setSheet(() {});
          }

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tamaño de hoja', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final paper in ScanPaper.values)
                        ChoiceChip(
                          label: Text(paper.label),
                          selected: _paper == paper,
                          onSelected: (_) => update(() => _paper = paper),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('Transcripción', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Mismo formato'),
                        selected: _keepForm,
                        onSelected: (_) => update(() => _keepForm = true),
                      ),
                      ChoiceChip(
                        label: const Text('Texto corrido'),
                        selected: !_keepForm,
                        onSelected: (_) => update(() => _keepForm = false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('Calidad del PDF', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final quality in ScanQuality.values)
                        ChoiceChip(
                          label: Text(quality.label),
                          selected: _quality == quality,
                          onSelected: (_) => update(() => _quality = quality),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _sayFailed() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('No se pudo preparar la página. Inténtalo de nuevo.')));
  }

  void _delete() {
    final index = _page;
    final path = _paths[index];
    setState(() {
      _paths.removeAt(index);
      _page = index.clamp(0, _paths.length - 1);
    });
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Página quitada.'),
        persist: false,
        action: SnackBarAction(
          label: 'Deshacer',
          onPressed: () {
            if (!mounted) return;
            setState(() => _paths.insert(index.clamp(0, _paths.length), path));
          },
        ),
      ),
    );
  }

  void _reorder(int from, int to) {
    setState(() {
      final path = _paths.removeAt(from);
      _paths.insert(to, path);
      _page = _paths.indexOf(path);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_pager.hasClients) _pager.jumpToPage(_page);
    });
  }

  @override
  void dispose() {
    _pager.dispose();
    for (final edits in _edits.values) {
      for (final edit in edits) {
        edit.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _finish() async {
    setState(() => _finishing = true);
    try {
      final paths = [..._paths];
      final retyped = _retype ? [for (final p in paths) await _edited(p)] : null;
      final ink = _retype ? [for (final p in paths) await _finalInk(p)] : null;
      final pages = [
        for (final p in paths) await compressScanPage(await _clean(p, await _effectiveFilter(p)), _quality),
      ];
      final options = (paper: _paper, quality: _quality, keepForm: _keepForm);
      final removed = _retype ? [for (final p in paths) _removedMarks(p)] : null;
      if (mounted) {
        Navigator.pop(context, (
          paths: paths,
          pages: pages,
          retyped: retyped,
          ink: ink,
          options: options,
          removedMarks: removed,
        ));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _finishing = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo preparar la página. Inténtalo de nuevo.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = _paths.length;
    return PremiumPage(
      title: 'Revisar escaneo',
      subtitle: total == 1 ? null : 'Página ${_page + 1} de $total',
      actions: [
        _finishing
            ? const PageAction.widget(SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
            : PageAction(icon: CupertinoIcons.checkmark, tooltip: 'Listo', onTap: _finish, primary: true),
      ],
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pager,
              itemCount: total,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => Padding(
                key: ValueKey('${_paths[i]}-${_versions[_paths[i]] ?? 0}'),
                padding: const EdgeInsets.all(16),
                child: _retype
                    ? _retypePage(_paths[i])
                    : FutureBuilder<CleanPage>(
                        future: _shownPage(_paths[i]),
                        builder: (context, snap) {
                          // Al cambiar de filtro FutureBuilder conserva la imagen
                          // anterior mientras espera: no se muestra la del otro filtro.
                          final page = snap.connectionState == ConnectionState.done ? snap.data : null;
                          if (page == null) {
                            return snap.hasError
                                ? Center(child: Text('No se pudo mostrar la página: ${snap.error}'))
                                : const Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircularProgressIndicator(),
                                        SizedBox(height: 16),
                                        Text('Preparando la página…'),
                                      ],
                                    ),
                                  );
                          }
                          return InteractiveViewer(maxScale: 5, child: _PageImage(page.jpeg));
                        },
                      ),
              ),
            ),
          ),
          _pageTools(),
          _blurNotice(),
          if (total > 0) _filterStrip(_paths[_page.clamp(0, total - 1)]),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Transcribir'),
                    selected: _retype,
                    onSelected: _finishing
                        ? null
                        : (_) {
                            if (!_retype) setState(_startRetype);
                          },
                  ),
                  if (total > 1 && !_retype)
                    FilterChip(
                      label: const Text('Solo esta página'),
                      selected: _onlyThisPage,
                      onSelected: _finishing ? null : (on) => setState(() => _onlyThisPage = on),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Cómo queda la página que se ve con cada filtro.
  Widget _filterStrip(String path) => SizedBox(
    height: 104,
    child: ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      children: [
        for (final f in ScanFilter.values)
          FutureBuilder<bool>(
            key: ValueKey('filtro-${f.name}-$path-${_versions[path] ?? 0}'),
            future: _usable(path, f),
            builder: (context, snap) {
              // Mientras se mide, se puede elegir: si borra, la página no lo lleva.
              final blocked = snap.data == false;
              return _FilterTile(
                label: f.label,
                preview: _thumb(path, f),
                blocked: blocked,
                selected: !_retype && !blocked && _filterOf(path) == f,
                onTap: _finishing || blocked ? null : () => _choose(f),
              );
            },
          ),
      ],
    ),
  );

  /// Conviene saberlo ahora, que todavía se puede repetir la foto.
  Widget _blurNotice() {
    final path = _paths[_page.clamp(0, _paths.length - 1)];
    return FutureBuilder<double>(
      key: ValueKey('nitidez-$path-${_versions[path] ?? 0}'),
      future: _sharpnessOf(path),
      builder: (context, snap) {
        final value = snap.data;
        if (value == null || value >= blurryBelow) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(
            'Esta página salió borrosa: se leerá peor. Si puedes, escanéala de nuevo.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFFFF9F0A)),
          ),
        );
      },
    );
  }

  /// Girar y quitar la página que se ve, y las miniaturas para ir a otra u
  /// ordenarlas arrastrando.
  Widget _pageTools() {
    final busy = _finishing || _rotating || _adding;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Girar la página',
            onPressed: busy ? null : _rotate,
            icon: const Icon(CupertinoIcons.rotate_right),
          ),
          IconButton(
            tooltip: 'Quitar la página',
            onPressed: busy || _paths.length < 2 ? null : _delete,
            icon: const Icon(CupertinoIcons.trash),
          ),
          if (widget.addPages != null)
            IconButton(
              tooltip: 'Agregar páginas',
              onPressed: busy ? null : _addPages,
              icon: _adding
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(CupertinoIcons.plus),
            ),
          if (_retype)
            IconButton(
              tooltip: 'Copiar el texto',
              onPressed: busy ? null : _copyText,
              icon: const Icon(CupertinoIcons.doc_on_clipboard),
            ),
          IconButton(
            tooltip: 'Tamaño y calidad del PDF',
            onPressed: busy ? null : _showPdfOptions,
            icon: const Icon(CupertinoIcons.slider_horizontal_3),
          ),
          const SizedBox(width: 8),
          if (_paths.length > 1)
            Expanded(
              child: SizedBox(
                height: 64,
                child: ReorderableListView(
                  scrollDirection: Axis.horizontal,
                  onReorderItem: _reorder,
                  buildDefaultDragHandles: true,
                  children: [
                    for (final (i, path) in _paths.indexed)
                      Padding(
                        key: ValueKey('mini-$path'),
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Semantics(
                          button: true,
                          label: 'Página ${i + 1}',
                          child: GestureDetector(
                            onTap: () => _pager.jumpToPage(i),
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  width: 2,
                                  color: i == _page ? Theme.of(context).colorScheme.primary : Colors.transparent,
                                ),
                              ),
                              child: Image.file(
                                File(path),
                                key: ValueKey(_versions[path] ?? 0),
                                height: 56,
                                cacheHeight: _thumbCacheHeight,
                                fit: BoxFit.contain,
                                excludeFromSemantics: true,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            )
          else
            const Spacer(),
        ],
      ),
    );
  }

  /// La foto original (el mejor detalle para comparar) y lo leído en ella.
  Widget _retypePage(String page) => FutureBuilder(
    // Siempre la misma espera: al redibujar no se pierde lo que se escribe.
    future: _compare.putIfAbsent(page, () => Future.wait([_clean(page, ScanFilter.original), _lines(page)])),
    builder: (context, snap) {
      if (snap.hasError) {
        return const Center(child: Text('No se pudo leer el texto de esta página.', textAlign: TextAlign.center));
      }
      final data = snap.data;
      if (data == null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(widget.readWithAi == null ? 'Leyendo la página…' : 'Leyendo con IA…'),
            ],
          ),
        );
      }
      final photo = data[0] as CleanPage;
      return RetypeEditor(
        photo: MemoryImage(photo.jpeg),
        width: photo.width,
        height: photo.height,
        lines: data[1] as List<ScannedLine>,
        controllers: _edits[page]!,
        doubts: _doubts[page] ?? const {},
        readByAi: _readByAi.contains(page),
        marks: _ink[page]?.marks ?? const [],
        hiddenMarks: _hiddenMarks[page] ?? const {},
        onToggleMark: (i) => setState(() {
          final hidden = _hiddenMarks.putIfAbsent(page, () => {});
          if (!hidden.remove(i)) hidden.add(i);
        }),
      );
    },
  );
}

/// Un filtro con la miniatura de cómo deja la página.
class _FilterTile extends StatelessWidget {
  const _FilterTile({
    required this.label,
    required this.preview,
    required this.selected,
    this.blocked = false,
    this.onTap,
  });

  final String label;
  final Future<CleanPage> preview;
  final bool selected;

  /// Borraría parte de la hoja: se ve apagado y dice por qué.
  final bool blocked;
  final VoidCallback? onTap;

  static const blockedNote = 'Borra datos';
  static const blockedReason = 'No disponible: este filtro borraría parte de la hoja.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tile = Semantics(
      button: true,
      enabled: !blocked,
      selected: selected,
      label: blocked ? '$label. $blockedReason' : label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              Opacity(
                opacity: blocked ? 0.35 : 1,
                child: Container(
                  width: 56,
                  height: 72,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    border: Border.all(width: 2, color: selected ? theme.colorScheme.primary : Colors.transparent),
                  ),
                  child: FutureBuilder<CleanPage>(
                    future: preview,
                    builder: (context, snap) => snap.data == null
                        ? const SizedBox.shrink()
                        : Image.memory(snap.data!.jpeg, fit: BoxFit.cover, gaplessPlayback: true),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                blocked ? blockedNote : label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(color: blocked ? theme.colorScheme.error : null),
              ),
            ],
          ),
        ),
      ),
    );
    return blocked ? Tooltip(message: blockedReason, triggerMode: TooltipTriggerMode.tap, child: tile) : tile;
  }
}

/// La hoja escaneada, entera y quieta.
class _PageImage extends StatelessWidget {
  const _PageImage(this.jpeg);
  final Uint8List jpeg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = Image.memory(jpeg, gaplessPlayback: true);
    // Sobre el fondo blanco una hoja blanca no se distingue: borde fino.
    if (theme.brightness == Brightness.dark) return Center(child: image);
    return Center(
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.22))),
        child: image,
      ),
    );
  }
}
