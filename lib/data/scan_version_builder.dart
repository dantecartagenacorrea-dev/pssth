import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/form_page.dart';
import '../domain/library_entry.dart';
import '../domain/retyped_pdf.dart';
import '../domain/scan_filters.dart';
import '../domain/scanned_pdf.dart';
import '../domain/text_chunk.dart';
import 'library_store.dart';

/// Páginas para [buildRetypedPdf] con el texto ya leído, sin foto ni posiciones
/// reales: cada frase va en su renglón, en el orden de lectura.
List<ScannedPage> pagesFromChunks(List<TextChunk> chunks) {
  final byPage = <int, List<String>>{};
  for (final c in chunks) {
    if (c.text.trim().isNotEmpty) (byPage[c.pageIndex] ??= []).add(c.text.trim());
  }
  final numbers = byPage.keys.toList()..sort();
  return [
    for (final n in numbers)
      (
        jpeg: Uint8List(0),
        width: 1000,
        height: 1400,
        lines: [
          for (final (i, text) in byPage[n]!.indexed)
            (text: text, left: 0.1, top: 0.05 + 0.9 * i / byPage[n]!.length, width: 0.8, height: 0.02),
        ],
      ),
  ];
}

/// Un PDF abierto para pasar sus páginas a imagen.
typedef ScanPdfPages = ({int count, Future<String> Function(int page, String out) render, Future<void> Function() close});

/// Margen alrededor del texto, para no cortar sellos ni firmas pegados a él.
const _sheetMargin = 0.08;

/// Una línea es de la hoja si al menos esta parte suya cae sobre el texto y no
/// se aleja de él más que esta fracción.
const _ruleInside = 0.5, _ruleReach = 0.25;
const _tableRows = 2;

/// El rectángulo de la hoja según dónde se leyó texto. null si hay muy poco
/// texto para saberlo: recortar a un solo renglón perdería el resto.
///
/// [rules]: las líneas de la hoja. Las que pasan por el texto entran enteras,
/// para no cortar un formulario; las de la mesa, lejos del texto, no.
({double left, double top, double right, double bottom})? sheetAround(
  List<ScannedLine> lines, {
  List<FormRule> rules = const [],
}) {
  final real = [
    for (final l in lines)
      if (l.text.trim().length >= 3) l,
  ];
  if (real.isEmpty) return null;
  var left = real.map((l) => l.left).reduce(math.min);
  var top = real.map((l) => l.top).reduce(math.min);
  var right = real.map((l) => l.left + l.width).reduce(math.max);
  var bottom = real.map((l) => l.top + l.height).reduce(math.max);
  if (right - left < 0.2 || bottom - top < 0.1) return null;
  final nearX = (right - left) * _ruleReach, nearY = (bottom - top) * _ruleReach;
  bool crosses(double a0, double a1, double b0, double b1) =>
      math.min(a1, b1) - math.max(a0, b0) > (a1 - a0) * _ruleInside;
  final (l0, t0, r0, b0) = (left, top, right, bottom);
  bool across(FormRule r) => r.y0 == r.y1 && crosses(r.x0, r.x1, l0, r0) && r.y0 > t0 - nearY && r.y1 < b0 + nearY;
  bool along(FormRule r) => r.x0 == r.x1 && crosses(r.y0, r.y1, t0, b0) && r.x0 > l0 - nearX && r.x1 < r0 + nearX;
  // Una raya vertical suelta es el borde del papel; una tabla tiene filas.
  final isTable = rules.where(across).length >= _tableRows;
  for (final r in rules) {
    if (!across(r) && !(isTable && along(r))) continue;
    left = math.min(left, r.x0);
    top = math.min(top, r.y0);
    right = math.max(right, r.x1);
    bottom = math.max(bottom, r.y1);
  }
  final x = (right - left) * _sheetMargin, y = (bottom - top) * _sheetMargin;
  return (
    left: math.max(0.0, left - x),
    top: math.max(0.0, top - y),
    right: math.min(1.0, right + x),
    bottom: math.min(1.0, bottom + y),
  );
}

/// Arma la primera vez las vistas que faltan de un documento y las deja
/// guardadas, para que la próxima abran al instante.
class ScanVersionBuilder {
  ScanVersionBuilder({
    required this.store,
    required this.recognize,
    required this.chunks,
    required this.pageCount,
    required this.openPages,
  });

  /// Para volver a leer un PDF escaneado página por página.
  final Future<ScanPdfPages> Function(String path) openPages;
  final LibraryStore store;
  final Future<List<ScannedLine>> Function(String path) recognize;

  /// Lo que la app ya leyó del documento abierto, y cuántas páginas tiene.
  final List<TextChunk> Function() chunks;
  final int Function() pageCount;

  final _running = <ScanVersion, Future<String>>{};

  /// La ruta de [version] en [entry]. Falla si no hay de dónde armarla.
  Future<String> prepare(LibraryEntry entry, ScanVersion version) async {
    final known = entry.versionPath(version);
    if (known != null && await File(known).exists()) return known;
    // Ir y volver de una vista mientras se arma no la arma dos veces.
    return _running[version] ??= _build(entry, version).whenComplete(() {
      _running.remove(version);
    });
  }

  Future<String> _build(LibraryEntry entry, ScanVersion version) => switch (version) {
    ScanVersion.original => throw const FileSystemException('El original ya no está guardado.'),
    ScanVersion.scanned => _scanCopy(entry),
    ScanVersion.clean => entry.kind == 'image'
        ? _cleanPhoto(entry)
        : entry.scanned
        ? _cleanScanned(entry)
        : _cleanText(entry),
  };

  /// Un PDF escaneado se relee: da mejor texto y conserva el formato. Si no se
  /// puede, queda el texto ya leído.
  Future<String> _cleanScanned(LibraryEntry entry) async {
    Uint8List? bytes;
    try {
      bytes = await _rereadPdf(entry);
    } catch (_) {
      bytes = null;
    }
    if (bytes == null) return _cleanText(entry);
    await store.attachScanVersions(entry, clean: bytes);
    return entry.cleanPath!;
  }

  /// Una hoja con sus negritas, firmas y sellos, para copiarla tal como es.
  Future<FormPage> _formPage(LibraryEntry entry, ScannedPage page) =>
      _withTemp(entry, page.jpeg, (path) async {
        final ink = await readInk(path, page.lines);
        final layer = await readFormLayer(path, page.lines, ink.marks);
        return (page: page, ink: ink, layer: layer);
      });

  Future<Uint8List?> _rereadPdf(LibraryEntry entry) async {
    // De la foto original si está: un filtro pudo borrar líneas del escaneado.
    final original = entry.originalPath;
    final source = original != null && await File(original).exists() ? original : entry.storedPath;
    final pdf = await openPages(source);
    try {
      final forms = <FormPage>[];
      for (var i = 0; i < pdf.count; i++) {
        final png = File('${store.root.path}/${entry.id}.temporal-p$i.png');
        final ({Uint8List jpeg, int width, int height}) photo;
        try {
          await pdf.render(i, png.path);
          photo = await originalScanPage(png.path);
        } finally {
          if (await png.exists()) await png.delete();
        }
        final lines = await _withTemp(entry, photo.jpeg, recognize);
        final page = (jpeg: photo.jpeg, width: photo.width, height: photo.height, lines: lines);
        forms.add(await _formPage(entry, page));
      }
      if (forms.every((f) => f.page.lines.isEmpty)) return null;
      return await buildFormPdf(forms, title: entry.name);
    } finally {
      await pdf.close();
    }
  }

  int _temps = 0;

  /// Da a [use] un archivo temporal con [jpeg] y lo borra al terminar.
  Future<T> _withTemp<T>(LibraryEntry entry, Uint8List jpeg, Future<T> Function(String path) use) async {
    final temp = File('${store.root.path}/${entry.id}.temporal${_temps++}.jpg');
    try {
      await temp.writeAsBytes(jpeg, flush: true);
      return await use(temp.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<ScannedPage>? _sheetOnce;

  /// La hoja de una foto importada: la foto no viene recortada como la del
  /// escáner, y la mesa alrededor saldría como manchas y líneas falsas.
  Future<ScannedPage> _sheet(LibraryEntry entry) => _sheetOnce ??= _readSheet(entry);

  Future<ScannedPage> _readSheet(LibraryEntry entry) async {
    final photo = await originalScanPage(entry.storedPath);
    final List<ScannedLine> first;
    try {
      first = await _withTemp(entry, photo.jpeg, recognize);
    } on Exception {
      return (jpeg: photo.jpeg, width: photo.width, height: photo.height, lines: const <ScannedLine>[]);
    }
    var rules = const <FormRule>[];
    try {
      rules = (await _withTemp(entry, photo.jpeg, (path) => readFormLayer(path, first, const []))).rules;
    } on Exception {
      // Sin medir las líneas se recorta solo por el texto.
    }
    final box = sheetAround(first, rules: rules);
    if (box == null) return (jpeg: photo.jpeg, width: photo.width, height: photo.height, lines: first);
    final sheet = await cropScanPage(photo.jpeg, box);
    // Las posiciones cambian al recortar: se leen de nuevo.
    final lines = await _withTemp(entry, sheet.jpeg, recognize);
    return (jpeg: sheet.jpeg, width: sheet.width, height: sheet.height, lines: lines);
  }

  Future<String> _scanCopy(LibraryEntry entry) async {
    final photo = await _sheet(entry);
    // «Limpio» solo si no borra nada (las tablas de un formulario, por ejemplo).
    var clean = await applyScanFilter(photo.jpeg, ScanFilter.limpio);
    if (await contentKept(photo.jpeg, clean.jpeg) < minContentKept) {
      clean = await applyScanFilter(photo.jpeg, ScanFilter.mejorar);
    }
    final bytes = await buildScannedPdf([
      (jpeg: clean.jpeg, width: clean.width, height: clean.height, lines: const <ScannedLine>[]),
    ], paper: ScanPaper.foto);
    await store.attachScanVersions(entry, scanCopy: bytes);
    return entry.scanCopyPath!;
  }

  /// Una foto se vuelve a leer, porque hacen falta las posiciones para
  /// mantener el formato; si no se puede medir, sale en texto corrido.
  Future<String> _cleanPhoto(LibraryEntry entry) async {
    final page = await _sheet(entry);
    if (page.lines.isEmpty) throw const FormatException('No se leyó texto en la foto.');
    Uint8List bytes;
    try {
      bytes = await buildFormPdf([await _formPage(entry, page)], title: entry.name);
    } catch (_) {
      bytes = await buildRetypedPdf([page], title: entry.name);
    }
    await store.attachScanVersions(entry, clean: bytes);
    return entry.cleanPath!;
  }

  Future<String> _cleanText(LibraryEntry entry) async {
    final read = chunks().where((c) => c.documentId == entry.id).toList();
    final pages = pagesFromChunks(read);
    if (pages.isEmpty) throw const FormatException('Todavía no hay texto leído.');
    final bytes = await buildRetypedPdf(pages, title: entry.name);
    final lastRead = read.map((c) => c.pageIndex).reduce((a, b) => a > b ? a : b);
    if (lastRead + 1 >= pageCount()) {
      await store.attachScanVersions(entry, clean: bytes);
      return entry.cleanPath!;
    }
    // Sigue leyendo el documento: se muestra lo que hay, sin guardarlo como final.
    final partial = File('${store.root.path}/${entry.id}.limpio-parcial.pdf');
    await partial.writeAsBytes(bytes, flush: true);
    return partial.path;
  }
}
