import 'dart:async';
import 'dart:io' show File;

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/motion.dart';
import '../domain/library_entry.dart';
import '../domain/text_chunk.dart';
import '../domain/text_locator.dart';
import '../playback/tts_audio_handler.dart';

/// Cómo se ve la página en pantalla completa.
enum ImmersiveMode { original, text }

/// Fondo del modo texto (como en un lector de libros).
enum ReadingPaper {
  white('Blanco', Color(0xFFFFFFFF), Color(0xFF111111)),
  sepia('Sepia', Color(0xFFF4ECD8), Color(0xFF4A3B2A)),
  black('Negro', Color(0xFF000000), Color(0xFFE6E6E6));

  const ReadingPaper(this.label, this.background, this.ink);
  final String label;
  final Color background, ink;
}

/// Lectura a pantalla completa, como un Kindle: la página original del PDF
/// (con la frase que suena resaltada en su lugar) o el texto limpio con fondo
/// blanco, sepia o negro. Tocar los costados pasa de página; el centro muestra
/// u oculta los controles. La página sigue a la voz.
class ImmersiveReader extends StatefulWidget {
  const ImmersiveReader({super.key, required this.handler, required this.entry});
  final TtsAudioHandler handler;
  final LibraryEntry entry;

  @override
  State<ImmersiveReader> createState() => _ImmersiveReaderState();
}

class _ImmersiveReaderState extends State<ImmersiveReader> {
  PdfDocument? _doc;
  // En un PDF, el último modo elegido aquí (Original si nunca se eligió).
  late ImmersiveMode _mode = widget.entry.kind == 'pdf'
      ? ImmersiveMode.values.asNameMap()[Comfort.readingMode.value] ?? ImmersiveMode.original
      : ImmersiveMode.text;
  // El último fondo elegido aquí; si nunca se eligió, el del tema de la app.
  ReadingPaper _paper =
      ReadingPaper.values.asNameMap()[Comfort.readingPaper.value] ??
      (Comfort.paper.value == Paper.black ? ReadingPaper.black : ReadingPaper.white);
  bool _controls = true;
  Timer? _hide;
  late PageController _pages = PageController(initialPage: _snapshotPage);
  int _shown = 0;

  /// El cambio de página lo hizo la voz (no la persona): no se reposiciona.
  bool _following = false;

  TtsAudioHandler get _h => widget.handler;
  int get _snapshotPage => _h.snapshot.value.pageIndex.clamp(0, 1 << 20);

  @override
  void initState() {
    super.initState();
    _shown = _snapshotPage;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _h.snapshot.addListener(_follow);
    _scheduleHide();
    if (widget.entry.kind == 'pdf') _openPdf();
  }

  Future<void> _openPdf() async {
    try {
      await pdfrxFlutterInitialize();
      final doc = await PdfDocument.openData(
        await File(widget.entry.storedPath).readAsBytes(),
        sourceName: widget.entry.storedPath,
        passwordProvider: () => null,
        firstAttemptByEmptyPassword: true,
      );
      if (!mounted) {
        await doc.dispose();
        return;
      }
      setState(() => _doc = doc);
    } catch (_) {
      // Sin la página original (protegido o dañado): queda el modo texto.
      if (mounted) _setMode(ImmersiveMode.text);
    }
  }

  @override
  void dispose() {
    _h.snapshot.removeListener(_follow);
    _hide?.cancel();
    _pages.dispose();
    _doc?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// La voz pasó a otra página: se muestra esa.
  void _follow() {
    final page = _snapshotPage;
    if (!mounted) return;
    if (page != _shown && _pages.hasClients) {
      _following = true;
      _pages.jumpToPage(page);
      _following = false;
    }
    setState(() => _shown = page);
  }

  /// La persona pasó de página: la lectura sigue desde ahí.
  void _onPageChanged(int page) {
    _shown = page;
    if (!_following && page != _snapshotPage) unawaited(_h.jumpToPage(page));
    setState(() {});
  }

  /// Original y Texto tienen cada uno su lista de páginas: la nueva arranca en
  /// la página que se está viendo.
  void _setMode(ImmersiveMode mode) {
    if (mode == _mode) return;
    final old = _pages;
    setState(() {
      _mode = mode;
      _pages = PageController(initialPage: _shown);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _scheduleHide();
  }

  void _scheduleHide() {
    _hide?.cancel();
    if (Comfort.keepControls.value) return;
    _hide = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _controls = false);
    });
  }

  void _toggleControls() {
    setState(() => _controls = !_controls);
    if (_controls) _scheduleHide();
  }

  void _turn(int delta) {
    final target = (_shown + delta).clamp(0, _pageCount - 1);
    if (target == _shown) return;
    _pages.animateToPage(target, duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
  }

  int get _pageCount {
    final doc = _doc;
    if (_mode == ImmersiveMode.original && doc != null) return doc.pages.length;
    final n = _h.snapshot.value.pageCount;
    return n > 0 ? n : 1;
  }

  Color get _background => _mode == ImmersiveMode.original ? const Color(0xFF1C1C1E) : _paper.background;
  Color get _ink => _mode == ImmersiveMode.original ? Colors.white : _paper.ink;

  @override
  Widget build(BuildContext context) {
    final waitingPdf = _mode == ImmersiveMode.original && _doc == null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _background.computeLuminance() > 0.5 ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: _background,
        body: Stack(
          children: [
            Positioned.fill(
              child: waitingPdf
                  ? const Center(child: CircularProgressIndicator())
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // Como en un lector de libros: los costados pasan de
                      // página y el centro muestra u oculta los controles.
                      onTapUp: (d) {
                        final w = MediaQuery.sizeOf(context).width;
                        if (d.globalPosition.dx < w * 0.2) return _turn(-1);
                        if (d.globalPosition.dx > w * 0.8) return _turn(1);
                        _toggleControls();
                      },
                      child: PageView.builder(
                        key: ValueKey(_mode),
                        controller: _pages,
                        itemCount: _pageCount,
                        onPageChanged: _onPageChanged,
                        itemBuilder: (context, i) => _mode == ImmersiveMode.original ? _originalPage(i) : _textPage(i),
                      ),
                    ),
            ),
            _overlay(context),
          ],
        ),
      ),
    );
  }

  // ---------- Original ----------

  Widget _originalPage(int i) {
    final doc = _doc!;
    final page = doc.pages[i];
    return LayoutBuilder(
      builder: (context, box) {
        final scale = [box.maxWidth / page.width, box.maxHeight / page.height].reduce((a, b) => a < b ? a : b);
        final size = Size(page.width * scale, page.height * scale);
        return InteractiveViewer(
          maxScale: 4,
          child: Center(
            child: SizedBox.fromSize(
              size: size,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: Colors.white,
                    child: PdfPageView(document: doc, pageNumber: i + 1),
                  ),
                  ValueListenableBuilder<PlayerSnapshot>(
                    valueListenable: _h.snapshot,
                    builder: (context, _, _) {
                      final chunk = _h.currentChunk;
                      if (chunk == null || chunk.pageIndex != i) return const SizedBox.shrink();
                      return _PageHighlight(
                        key: ValueKey('${chunk.pageIndex}-${chunk.chunkIndex}'),
                        page: page,
                        size: size,
                        snippet: chunk.text,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------- Texto ----------

  Widget _textPage(int i) {
    final chunks = [
      for (final c in _h.chunks)
        if (c.pageIndex == i) c,
    ];
    return SafeArea(
      child: ListenableBuilder(
        listenable: Listenable.merge([_h.snapshot, Comfort.textSize, Comfort.lineHeight, Comfort.legible]),
        builder: (context, _) => _TextPage(
          chunks: chunks,
          current: _h.currentChunk,
          ink: _ink,
          accent: _paper == ReadingPaper.black ? const Color(0x55FAC775) : const Color(0x40BA7517),
          style: TextStyle(
            fontFamily: Comfort.readingFont,
            fontSize: Comfort.textSize.value + 2,
            height: Comfort.lineHeight.value.height + 0.1,
            color: _ink,
          ),
        ),
      ),
    );
  }

  // ---------- Controles ----------

  Widget _overlay(BuildContext context) {
    final hasPdf = widget.entry.kind == 'pdf' && _doc != null;
    return IgnorePointer(
      ignoring: !_controls,
      child: AnimatedOpacity(
        opacity: _controls ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                _Bar(
                  children: [
                    IconButton(
                      tooltip: 'Salir de pantalla completa',
                      icon: const Icon(CupertinoIcons.xmark, color: Colors.white),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: Text(
                        'Página ${_shown + 1} de $_pageCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (hasPdf)
                      _Choice(
                        options: const ['Original', 'Texto'],
                        selected: _mode.index,
                        onSelect: (v) {
                          _setMode(ImmersiveMode.values[v]);
                          unawaited(Comfort.setReadingMode(ImmersiveMode.values[v].name));
                        },
                      ),
                    if (_mode == ImmersiveMode.text) ...[
                      const SizedBox(width: 8),
                      for (final p in ReadingPaper.values)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Tooltip(
                            message: 'Fondo ${p.label.toLowerCase()}',
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () {
                                setState(() {
                                  _paper = p;
                                  _scheduleHide();
                                });
                                unawaited(Comfort.setReadingPaper(p.name));
                              },
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: p.background,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _paper == p ? Colors.white : Colors.white38,
                                    width: _paper == p ? 2.5 : 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
                const Spacer(),
                ValueListenableBuilder<PlayerSnapshot>(
                  valueListenable: _h.snapshot,
                  builder: (context, s, _) => _Bar(
                    center: true,
                    children: [
                      IconButton(
                        tooltip: 'Frase anterior',
                        icon: const Icon(CupertinoIcons.gobackward, color: Colors.white),
                        onPressed: s.hasText ? _h.skipToPrevious : null,
                      ),
                      const SizedBox(width: 12),
                      Material(
                        color: Colors.white,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: s.hasText ? () => s.playing ? _h.pause() : _h.play() : null,
                          child: SizedBox.square(
                            dimension: 52,
                            child: Icon(
                              s.playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                              color: Colors.black,
                              semanticLabel: s.playing ? 'Pausa' : 'Reproducir',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        tooltip: 'Frase siguiente',
                        icon: const Icon(CupertinoIcons.goforward, color: Colors.white),
                        onPressed: s.hasText ? _h.skipToNext : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Barra de controles: píldora negra translúcida.
class _Bar extends StatelessWidget {
  const _Bar({required this.children, this.center = false});
  final List<Widget> children;
  final bool center;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: center ? 320 : 760),
      child: Material(
        color: const Color(0xE6151515),
        shape: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: children),
        ),
      ),
    ),
  );
}

/// Original / Texto en píldoras.
class _Choice extends StatelessWidget {
  const _Choice({required this.options, required this.selected, required this.onSelect});
  final List<String> options;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (i, label) in options.indexed)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Material(
            color: i == selected ? Colors.white : Colors.transparent,
            shape: const StadiumBorder(side: BorderSide(color: Colors.white24)),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => onSelect(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                child: Text(
                  label,
                  style: TextStyle(
                    color: i == selected ? Colors.black : Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

/// La frase que suena, marcada en su lugar de la página original.
class _PageHighlight extends StatefulWidget {
  const _PageHighlight({super.key, required this.page, required this.size, required this.snippet});
  final PdfPage page;
  final Size size;
  final String snippet;

  /// Texto de cada página con la ubicación de sus letras (se lee una vez).
  static final _texts = Expando<Map<int, Future<PdfPageRawText?>>>();

  @override
  State<_PageHighlight> createState() => _PageHighlightState();
}

class _PageHighlightState extends State<_PageHighlight> {
  List<Rect> _rects = const [];

  @override
  void initState() {
    super.initState();
    _locate();
  }

  Future<void> _locate() async {
    final page = widget.page;
    final cache = _PageHighlight._texts[page.document] ??= {};
    final raw = await (cache[page.pageNumber] ??= page.loadText());
    if (raw == null || !mounted) return;
    final r = locateSnippet(raw.fullText, widget.snippet);
    if (r == null) return;
    final chars = [
      for (var i = r.start; i < r.end && i < raw.charRects.length; i++)
        raw.charRects[i].toRect(page: page, scaledPageSize: widget.size),
    ];
    final lines = mergeLines([for (final c in chars) (left: c.left, top: c.top, right: c.right, bottom: c.bottom)]);
    if (mounted) setState(() => _rects = [for (final l in lines) Rect.fromLTRB(l.left, l.top, l.right, l.bottom)]);
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(child: CustomPaint(painter: _Marks(_rects)));
}

class _Marks extends CustomPainter {
  _Marks(this.rects);
  final List<Rect> rects;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0x55FFC94A);
    for (final r in rects) {
      canvas.drawRRect(RRect.fromRectAndRadius(r.inflate(2), const Radius.circular(3)), paint);
    }
  }

  @override
  bool shouldRepaint(_Marks old) => old.rects != rects;
}

/// Una página en modo texto: la frase que suena con fondo suave y la vista
/// la sigue.
class _TextPage extends StatefulWidget {
  const _TextPage({
    required this.chunks,
    required this.current,
    required this.ink,
    required this.accent,
    required this.style,
  });
  final List<TextChunk> chunks;
  final TextChunk? current;
  final Color ink, accent;
  final TextStyle style;

  @override
  State<_TextPage> createState() => _TextPageState();
}

class _TextPageState extends State<_TextPage> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant _TextPage old) {
    super.didUpdateWidget(old);
    final i = widget.chunks.indexWhere((c) => identical(c, widget.current));
    if (i < 0 || !_scroll.hasClients || widget.chunks.length < 2) return;
    // La frase que suena, a un tercio de la pantalla.
    final target = _scroll.position.maxScrollExtent * (i / (widget.chunks.length - 1));
    _scroll.animateTo(target, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(32, 56, 32, 120),
        child: Text.rich(
          TextSpan(
            style: widget.style,
            children: [
              for (final (i, c) in widget.chunks.indexed)
                // Los títulos (en mayúsculas) van en su propio renglón, como en
                // un libro; el resto corre como párrafo.
                _isHeading(c.text)
                    ? TextSpan(
                        // Un título partido en varias frases va en renglones
                        // seguidos; antes de un título nuevo, un espacio.
                        text: '${i == 0 || _isHeading(widget.chunks[i - 1].text) ? '' : '\n\n'}${c.text}\n',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                          backgroundColor: identical(c, widget.current) ? widget.accent : null,
                        ),
                      )
                    : TextSpan(
                        text: '${c.text} ',
                        style: identical(c, widget.current) ? TextStyle(backgroundColor: widget.accent) : null,
                      ),
            ],
          ),
          textAlign: TextAlign.justify,
        ),
      ),
    ),
  );
}

final _letters = RegExp(r'\p{L}', unicode: true);
final _upper = RegExp(r'\p{Lu}', unicode: true);

/// ¿Es un título? Casi todas sus letras en mayúscula (y es corto).
bool _isHeading(String text) {
  final letters = _letters.allMatches(text).length;
  if (letters < 3 || text.length > 120) return false;
  return _upper.allMatches(text).length / letters > 0.8;
}
