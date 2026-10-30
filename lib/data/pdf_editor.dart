import 'dart:async';
import 'dart:ffi';
import 'dart:io' show File;
import 'dart:ui' show Offset, Rect;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:pdfium_dart/pdfium_dart.dart' as pf;
import 'package:pdfrx/pdfrx.dart';

/// PDFium, el mismo que carga pdfrx (se busca una sola vez).
final pf.PDFium _pdfium = pf.getPdfium(modulePath: Pdfrx.pdfiumModulePath);

/// Color RGBA (0–255) de una marca.
typedef Rgba = ({int r, int g, int b, int a});

const Rgba kHighlightYellow = (r: 255, g: 214, b: 0, a: 110);
const Rgba kInkBlue = (r: 20, g: 60, b: 200, a: 255);
const Rgba kTextBlack = (r: 0, g: 0, b: 0, a: 255);
const Rgba kNoteYellow = (r: 255, g: 200, b: 0, a: 255);

/// Lo que se puede deshacer, de lo último a lo primero.
sealed class _Undo {}

/// El documento entero antes de un cambio de páginas.
final class _Snapshot extends _Undo {
  _Snapshot(this.bytes);
  final Uint8List bytes;
}

/// Anotación agregada al final de la lista de la página.
final class _AnnotAdded extends _Undo {
  _AnnotAdded(this.page, this.index);
  final int page, index;
}

/// Objetos (recuadro, texto) agregados al final del contenido de la página.
final class _ObjectsAdded extends _Undo {
  _ObjectsAdded(this.page, this.from);
  final int page, from;
}

/// Edición de una copia de un PDF en memoria: organizar páginas (rotar, quitar,
/// mover, unir con otro PDF), anotar (resaltar, lápiz, notas, firma) y
/// escribir o corregir texto (recuadro blanco y texto encima). El archivo
/// original nunca se toca: [save] devuelve los bytes del PDF nuevo.
///
/// Las posiciones llegan normalizadas (0–1) sobre la página tal como se ve
/// (con su giro), con el origen arriba a la izquierda.
class PdfEditor {
  PdfEditor._(this._doc, this.signed);

  PdfDocument _doc;

  /// El documento que se ve (cambia al reordenar páginas: se vuelve a abrir).
  PdfDocument get doc => _doc;

  /// Tiene firma digital: al editarlo deja de ser válida.
  final bool signed;

  /// Avisa cada cambio (la vista vuelve a dibujar las páginas).
  final ValueNotifier<int> changes = ValueNotifier(0);
  final List<_Undo> _undo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get edited => changes.value > 0;
  int get pageCount => doc.pages.length;

  static Future<PdfEditor> openFile(String path) async {
    // En memoria: abierto desde el archivo, PDFium lee por un puente del hilo
    // de pdfrx y anotar desde la app lo hacía caer.
    final doc = await PdfDocument.openData(
      await File(path).readAsBytes(),
      sourceName: path,
      passwordProvider: () => null,
      firstAttemptByEmptyPassword: true,
    );
    final signed = await doc.useNativeDocumentHandle((h) => _pdfium.FPDF_GetSignatureCount(_docPtr(h)) > 0);
    return PdfEditor._(doc, signed);
  }

  Future<void> dispose() => _doc.dispose();

  void _changed() => changes.value++;

  // ---------- Páginas ----------

  // Se hacen con PDFium y el documento se vuelve a abrir: el reordenamiento
  // de pdfrx 2.4.8 pierde el número original de cada página y guardaba el
  // orden viejo.

  /// Gira la página 90° a la derecha.
  Future<void> rotate(int i) => _pagesOp((d) {
    final page = _pdfium.FPDF_LoadPage(d, i);
    _pdfium.FPDFPage_SetRotation(page, (_pdfium.FPDFPage_GetRotation(page) + 1) % 4);
    _pdfium.FPDF_ClosePage(page);
  });

  /// Quita la página (siempre queda al menos una).
  Future<void> removePage(int i) async {
    if (pageCount <= 1) return;
    await _pagesOp((d) => _pdfium.FPDFPage_Delete(d, i));
  }

  Future<void> movePage(int from, int to) async {
    if (from == to || to < 0 || to >= pageCount) return;
    await _pagesOp(
      (d) => using((arena) {
        final index = arena<Int>()..value = from;
        _pdfium.FPDF_MovePages(d, index, 1, to);
      }),
    );
  }

  /// Agrega al final las páginas de otro PDF.
  Future<void> appendFile(String path) => _pagesOp(
    (d) => using((arena) {
      final other = _pdfium.FPDF_LoadDocument(path.toNativeUtf8(allocator: arena).cast(), nullptr);
      if (other == nullptr) throw const FormatException('No se pudo abrir el otro PDF');
      try {
        _pdfium.FPDF_ImportPagesByIndex(d, other, nullptr, 0, _pdfium.FPDF_GetPageCount(d));
      } finally {
        _pdfium.FPDF_CloseDocument(other);
      }
    }),
  );

  Future<void> _pagesOp(void Function(pf.FPDF_DOCUMENT d) op) async {
    final before = await _doc.encodePdf();
    final handle = await _doc.useNativeDocumentHandle((h) => h);
    await PdfrxEntryFunctions.instance.compute(_runOnDoc, (doc: handle, work: op));
    await _reopen(await _doc.encodePdf());
    _undo.add(_Snapshot(before));
    _changed();
  }

  Future<void> _reopen(Uint8List bytes) async {
    final old = _doc;
    _doc = await PdfDocument.openData(bytes, sourceName: 'edicion-${DateTime.now().microsecondsSinceEpoch}');
    // La vista pudo pedirle una página al anterior justo ahora.
    unawaited(Future.delayed(const Duration(seconds: 2), old.dispose));
  }

  // ---------- Anotar ----------
  // Todo lo que toca PDFium corre en el hilo de pdfrx (sus fuentes y lecturas
  // responden ahí; desde otro hilo la app se cerraba). Por eso cada trabajo se
  // arma en una función aparte, sin referencias al editor.

  /// Resalta un área (marcador amarillo transparente).
  Future<void> highlight(int pageIndex, Rect area, {Rgba color = kHighlightYellow}) =>
      _addAnnot(pageIndex, pf.FPDF_ANNOT_HIGHLIGHT, _highlightFill(area, color));

  /// Trazos a mano (lápiz o firma). [width] en puntos.
  Future<void> ink(int pageIndex, List<List<Offset>> strokes, {Rgba color = kInkBlue, double width = 2}) {
    final lines = strokes.where((s) => s.length > 1).toList();
    if (lines.isEmpty) return Future.value();
    return _addAnnot(pageIndex, pf.FPDF_ANNOT_INK, _inkFill(lines, color, width));
  }

  /// Nota adhesiva (ícono) con [text] en [at].
  Future<void> note(int pageIndex, Offset at, String text) =>
      _addAnnot(pageIndex, pf.FPDF_ANNOT_TEXT, _noteFill(at, text));

  /// Escribe [text] (puede tener varios renglones) con la esquina de arriba a
  /// la izquierda en [at]. [size] en puntos.
  Future<void> addText(int pageIndex, Offset at, String text, {double size = 12, Rgba color = kTextBlack}) =>
      _addObjects(pageIndex, _textWork(at, text, size, color));

  /// Corrige: tapa [area] con blanco y escribe [text] encima, del alto del
  /// área (lo de abajo sigue en el archivo: no sirve para ocultar datos).
  Future<void> correct(int pageIndex, Rect area, String text) => _addObjects(pageIndex, _correctWork(area, text));

  // ---------- Deshacer y guardar ----------

  Future<void> undo() async {
    if (_undo.isEmpty) return;
    final last = _undo.removeLast();
    switch (last) {
      case _Snapshot(:final bytes):
        await _reopen(bytes);
      case _AnnotAdded(:final page, :final index):
        await _withPage(page, _removeAnnotWork(index));
      case _ObjectsAdded(:final page, :final from):
        await _withPage(page, _removeObjectsWork(from));
    }
    _changed();
  }

  /// El PDF editado (una copia nueva; el original queda igual).
  Future<Uint8List> save() => doc.encodePdf();

  /// Tipos de las anotaciones de una página (para pruebas).
  @visibleForTesting
  static Future<List<String>> annotationKinds(PdfDocument doc, int pageIndex) =>
      _onPageOf(doc, pageIndex, _annotKindsWork);

  // ---------- PDFium ----------

  Future<void> _addAnnot(int pageIndex, int subtype, _AnnotFill fill) async {
    final index = await _withPage(pageIndex, _annotWork(subtype, fill));
    _undo.add(_AnnotAdded(pageIndex, index));
    _changed();
  }

  Future<void> _addObjects(int pageIndex, _PageWork<void> add) async {
    final from = await _withPage(pageIndex, _objectsWork(add));
    _undo.add(_ObjectsAdded(pageIndex, from));
    _changed();
  }

  Future<T> _withPage<T>(int pageIndex, _PageWork<T> work) => _onPageOf(_doc, pageIndex, work);
}

/// Trabajo sobre una página abierta (corre en el hilo de pdfrx).
typedef _PageWork<T> = T Function(_Page p);

/// Rellena una anotación recién creada.
typedef _AnnotFill = void Function(_Page p, pf.FPDF_ANNOTATION annot);

/// Página abierta en PDFium con lo necesario para dibujar en ella.
class _Page {
  _Page(this.doc, this.page, this.arena) : map = _PageMap(page);
  final pf.FPDF_DOCUMENT doc;
  final pf.FPDF_PAGE page;
  final Arena arena;
  final _PageMap map;
}

Future<T> _onPageOf<T>(PdfDocument doc, int pageIndex, _PageWork<T> work) async {
  final handle = await doc.useNativeDocumentHandle((h) => h);
  return PdfrxEntryFunctions.instance.compute(_runOnPage<T>, (doc: handle, page: pageIndex, work: work));
}

void _runOnDoc(({int doc, void Function(pf.FPDF_DOCUMENT d) work}) m) => m.work(_docPtr(m.doc));

T _runOnPage<T>(({int doc, int page, _PageWork<T> work}) m) {
  final d = _docPtr(m.doc);
  final page = _pdfium.FPDF_LoadPage(d, m.page);
  if (page == nullptr) throw StateError('PDFium no abrió la página ${m.page}');
  try {
    return using((arena) => m.work(_Page(d, page, arena)));
  } finally {
    _pdfium.FPDF_ClosePage(page);
  }
}

_PageWork<int> _annotWork(int subtype, _AnnotFill fill) => (p) {
  final annot = _pdfium.FPDFPage_CreateAnnot(p.page, subtype);
  if (annot == nullptr) throw StateError('PDFium no creó la anotación');
  try {
    fill(p, annot);
    _pdfium.FPDFAnnot_SetFlags(annot, pf.FPDF_ANNOT_FLAG_PRINT);
  } finally {
    _pdfium.FPDFPage_CloseAnnot(annot);
  }
  return _pdfium.FPDFPage_GetAnnotCount(p.page) - 1;
};

_PageWork<int> _objectsWork(_PageWork<void> add) => (p) {
  final before = _pdfium.FPDFPage_CountObjects(p.page);
  add(p);
  _pdfium.FPDFPage_GenerateContent(p.page);
  return before;
};

_PageWork<void> _removeAnnotWork(int index) => (p) => _pdfium.FPDFPage_RemoveAnnot(p.page, index);

_PageWork<void> _removeObjectsWork(int from) => (p) {
  for (var i = _pdfium.FPDFPage_CountObjects(p.page) - 1; i >= from; i--) {
    final obj = _pdfium.FPDFPage_GetObject(p.page, i);
    if (_pdfium.FPDFPage_RemoveObject(p.page, obj) != 0) _pdfium.FPDFPageObj_Destroy(obj);
  }
  _pdfium.FPDFPage_GenerateContent(p.page);
};

List<String> _annotKindsWork(_Page p) => [
  for (var i = 0; i < _pdfium.FPDFPage_GetAnnotCount(p.page); i++)
    switch (_annotSubtype(p.page, i)) {
      pf.FPDF_ANNOT_HIGHLIGHT => 'highlight',
      pf.FPDF_ANNOT_INK => 'ink',
      pf.FPDF_ANNOT_TEXT => 'note',
      final other => '$other',
    },
];

int _annotSubtype(pf.FPDF_PAGE page, int i) {
  final annot = _pdfium.FPDFPage_GetAnnot(page, i);
  try {
    return _pdfium.FPDFAnnot_GetSubtype(annot);
  } finally {
    _pdfium.FPDFPage_CloseAnnot(annot);
  }
}

_AnnotFill _highlightFill(Rect area, Rgba color) => (p, annot) {
  final r = p.map.rect(area);
  final quad = p.arena<pf.FS_QUADPOINTSF>();
  quad.ref
    ..x1 = r.left
    ..y1 = r.top
    ..x2 = r.right
    ..y2 = r.top
    ..x3 = r.left
    ..y3 = r.bottom
    ..x4 = r.right
    ..y4 = r.bottom;
  _pdfium.FPDFAnnot_AppendAttachmentPoints(annot, quad);
  _setRect(annot, r, p.arena);
  _color(annot, color);
};

_AnnotFill _inkFill(List<List<Offset>> lines, Rgba color, double width) => (p, annot) {
  var bounds = _PdfRect.empty;
  for (final s in lines) {
    final points = p.arena<pf.FS_POINTF>(s.length);
    for (var i = 0; i < s.length; i++) {
      final at = p.map.point(s[i]);
      points[i]
        ..x = at.x
        ..y = at.y;
      bounds = bounds.include(at.x, at.y);
    }
    _pdfium.FPDFAnnot_AddInkStroke(annot, points, s.length);
  }
  _pdfium.FPDFAnnot_SetBorder(annot, 0, 0, width);
  _setRect(annot, bounds.inflate(width), p.arena);
  _color(annot, color);
};

_AnnotFill _noteFill(Offset at, String text) => (p, annot) {
  final pt = p.map.point(at);
  _setRect(annot, _PdfRect(pt.x, pt.y - 20, pt.x + 20, pt.y), p.arena);
  _pdfium.FPDFAnnot_SetStringValue(annot, 'Contents'.toNativeUtf8(allocator: p.arena).cast(), _wide(text, p.arena));
  _color(annot, kNoteYellow);
};

_PageWork<void> _textWork(Offset at, String text, double size, Rgba color) =>
    (p) => _writeText(p, at, text, size, color);

_PageWork<void> _correctWork(Rect area, String text) => (p) {
  final r = p.map.rect(area);
  final box = _pdfium.FPDFPageObj_CreateNewRect(r.left, r.bottom, r.right - r.left, r.top - r.bottom);
  _pdfium.FPDFPageObj_SetFillColor(box, 255, 255, 255, 255);
  _pdfium.FPDFPath_SetDrawMode(box, pf.FPDF_FILLMODE_ALTERNATE, 0);
  _pdfium.FPDFPage_InsertObject(p.page, box);
  if (text.trim().isEmpty) return;
  final map = p.map;
  final size = (area.height * map.displayHeight * 0.75).clamp(4.0, 72.0);
  // Renglón centrado en el alto del área.
  final top = Offset(area.left + 1 / map.displayWidth, area.top + (area.height - size * 1.15 / map.displayHeight) / 2);
  _writeText(p, top, text.trim(), size, kTextBlack);
};

void _writeText(_Page p, Offset at, String text, double size, Rgba color) {
  final map = p.map;
  final font = _pdfium.FPDFText_LoadStandardFont(p.doc, 'Helvetica'.toNativeUtf8(allocator: p.arena).cast());
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].isEmpty) continue;
    final obj = _pdfium.FPDFPageObj_CreateTextObj(p.doc, font, size);
    _pdfium.FPDFText_SetText(obj, _wide(lines[i], p.arena));
    _pdfium.FPDFPageObj_SetFillColor(obj, color.r, color.g, color.b, color.a);
    // Línea base de cada renglón, bajando como se ve la página; el texto se
    // gira con la página para que se lea derecho.
    final base = map.point(Offset(at.dx, at.dy + (i + 0.85) * size * 1.2 / map.displayHeight));
    final turn = map.rotation; // cuartos de vuelta a la derecha
    const cos = [1.0, 0.0, -1.0, 0.0], sin = [0.0, 1.0, 0.0, -1.0];
    _pdfium.FPDFPageObj_Transform(obj, cos[turn], sin[turn], -sin[turn], cos[turn], base.x, base.y);
    _pdfium.FPDFPage_InsertObject(p.page, obj);
  }
  _pdfium.FPDFFont_Close(font);
}

void _setRect(pf.FPDF_ANNOTATION annot, _PdfRect r, Arena arena) {
  final rect = arena<pf.FS_RECTF>();
  rect.ref
    ..left = r.left
    ..top = r.top
    ..right = r.right
    ..bottom = r.bottom;
  _pdfium.FPDFAnnot_SetRect(annot, rect);
}

void _color(pf.FPDF_ANNOTATION annot, Rgba c) =>
    _pdfium.FPDFAnnot_SetColor(annot, pf.FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color, c.r, c.g, c.b, c.a);

pf.FPDF_DOCUMENT _docPtr(int handle) => pf.FPDF_DOCUMENT.fromAddress(handle);

/// Texto en UTF-16 terminado en cero, como lo pide PDFium.
pf.FPDF_WIDESTRING _wide(String s, Arena arena) {
  final units = s.codeUnits;
  final p = arena<Uint16>(units.length + 1);
  for (var i = 0; i < units.length; i++) {
    p[i] = units[i];
  }
  p[units.length] = 0;
  return p.cast();
}

/// Rectángulo en puntos del PDF (origen abajo a la izquierda).
class _PdfRect {
  const _PdfRect(this.left, this.bottom, this.right, this.top);
  final double left, bottom, right, top;

  static const empty = _PdfRect(double.infinity, double.infinity, -double.infinity, -double.infinity);

  _PdfRect include(double x, double y) =>
      _PdfRect(x < left ? x : left, y < bottom ? y : bottom, x > right ? x : right, y > top ? y : top);

  _PdfRect inflate(double d) => _PdfRect(left - d, bottom - d, right + d, top + d);
}

/// Pasa de la página como se ve (0–1, con su giro) a puntos del PDF.
class _PageMap {
  _PageMap(this.page)
    : rotation = _pdfium.FPDFPage_GetRotation(page) % 4,
      width = _pdfium.FPDF_GetPageWidthF(page),
      height = _pdfium.FPDF_GetPageHeightF(page);

  final pf.FPDF_PAGE page;
  final int rotation;
  final double width, height;

  /// Medidas de la página como se ve, en puntos.
  double get displayWidth => rotation.isOdd ? height : width;
  double get displayHeight => rotation.isOdd ? width : height;

  /// Precisión de la conversión: unidades de pantalla por punto.
  static const _scale = 20;

  ({double x, double y}) point(Offset normalized) => using((arena) {
    final x = arena<Double>(), y = arena<Double>();
    final w = (displayWidth * _scale).round(), h = (displayHeight * _scale).round();
    _pdfium.FPDF_DeviceToPage(
      page,
      0,
      0,
      w,
      h,
      rotation,
      (normalized.dx * w).round(),
      (normalized.dy * h).round(),
      x,
      y,
    );
    return (x: x.value, y: y.value);
  });

  _PdfRect rect(Rect normalized) {
    final a = point(normalized.topLeft), b = point(normalized.bottomRight);
    return _PdfRect(
      a.x < b.x ? a.x : b.x,
      a.y < b.y ? a.y : b.y,
      a.x > b.x ? a.x : b.x,
      a.y > b.y ? a.y : b.y,
    );
  }
}
