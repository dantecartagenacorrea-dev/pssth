import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../data/model_store.dart';
import '../domain/math/fraction_bars.dart';
import '../domain/math/latex_math.dart';
import '../domain/math/stacked_math.dart';
import '../domain/scanned_pdf.dart' show ScannedLine;
import '../domain/scan_filters.dart';
import 'formula_engine.dart';

/// Lado de la imagen que espera el modelo.
const formulaImageSize = 384;
const _maxSide = 1600;
const _margin = 24;

/// Lee fórmulas de una foto con el modelo descargable. Da el texto que entiende
/// la calculadora, o null si el modelo no está o no se pudo leer: entonces sigue
/// el lector común, así que nunca es un error para la persona.
class FormulaModelReader {
  FormulaModelReader(this.store);
  final ModelStore store;

  static List<String>? _vocabulary;

  bool get installed => store.isInstalled(formulaModel);

  Future<String?> read(String path) async => (await readChecked(path, const [])).plain;

  /// Lee la foto entera y, si tiene fracciones, también cada número por separado
  /// junto a los signos que se ven: [FormulaReading.check] es esa segunda lectura.
  /// [lines] es lo que vio el lector común (para los enteros sueltos).
  Future<FormulaReading> readChecked(String path, List<ScannedLine> lines) async {
    if (!installed) return const FormulaReading();
    try {
      final dir = store.dirFor(formulaModel).path;
      final vocabulary = _vocabulary ?? await Isolate.run<List<String>>(() => _loadVocabulary('$dir/tokenizer.json'));
      _vocabulary = vocabulary;
      final encoder = '$dir/encoder_model.onnx', decoder = '$dir/decoder_model.onnx';
      final scan = await Isolate.run(() => _readAll(path, encoder, decoder));
      if (scan == null) return const FormulaReading();
      final plain = latexToPlain(decodeFormulaTokens(scan.whole, vocabulary));
      if (scan.fractions.isEmpty) return FormulaReading(plain: plain);
      final fractions = <ReadFraction>[];
      for (final f in scan.fractions) {
        final top = numberFromLatex(decodeFormulaTokens(f.top, vocabulary));
        final bottom = numberFromLatex(decodeFormulaTokens(f.bottom, vocabulary));
        if (top == null || bottom == null) return FormulaReading(plain: plain, fractions: scan.fractions.length);
        fractions.add((text: '$top/$bottom', left: f.left, right: f.right, top: f.top0, bottom: f.bottom0));
      }
      final check = assembleFractions(fractions, [
        for (final line in lines)
          if (!scan.signs.any((s) => line.left + line.width / 2 >= s.from && line.left + line.width / 2 <= s.to)) line,
        for (final s in scan.signs) (text: s.text, left: s.x, top: s.y, width: 0.001, height: 0.001),
      ]);
      return FormulaReading(plain: plain, check: check, fractions: scan.fractions.length);
    } on FormulaEngineException {
      return const FormulaReading();
    } on FileSystemException {
      return const FormulaReading();
    } on FormatException {
      return const FormulaReading();
    }
  }
}

/// Lo que dio el lector de fórmulas: [plain], la lectura de la foto entera;
/// [check], la armada número por número; [fractions], las rayas que se ven.
class FormulaReading {
  const FormulaReading({this.plain, this.check, this.fractions = 0});
  final String? plain;
  final String? check;
  final int fractions;
}

typedef _FractionIds = ({List<int> top, List<int> bottom, double left, double right, double top0, double bottom0});
typedef _Sign = ({String text, double x, double y, double from, double to});
typedef _Scan = ({List<int> whole, List<_FractionIds> fractions, List<_Sign> signs});

const _maxFractions = 6;

_Scan? _readAll(String path, String encoder, String decoder) {
  final prepared = _prepare(path);
  if (prepared == null) return null;
  final page = prepared.page;
  final w = page.width, h = page.height;
  final bars = findFractionBars(prepared.ink, w, h);
  final useBars = bars.length <= _maxFractions ? bars : const <FractionBar>[];
  final images = <Float32List>[
    _pixels(_crop(page, prepared.box, _margin)),
    for (final bar in useBars) ...[
      _pixels(_squareNumber(page, bar.numerator)),
      _pixels(_squareNumber(page, bar.denominator)),
    ],
  ];
  final ids = runFormulaModel(encoder, decoder, images, formulaImageSize);
  final signs = <_Sign>[
    for (var i = 1; i < useBars.length; i++)
      if (classifyOperator(prepared.ink, w, (
            left: useBars[i - 1].right + 2,
            top: math.min(useBars[i - 1].numerator.top, useBars[i].numerator.top),
            right: useBars[i].left - 2,
            bottom: math.max(useBars[i - 1].denominator.bottom, useBars[i].denominator.bottom),
          ))
          case final sign?)
        (
          text: sign,
          x: (useBars[i - 1].right + useBars[i].left) / 2 / w,
          y: useBars[i].y / h,
          from: useBars[i - 1].right / w,
          to: useBars[i].left / w,
        ),
  ];
  return (
    whole: ids.first,
    fractions: [
      for (final (i, bar) in useBars.indexed)
        (
          top: ids[1 + i * 2],
          bottom: ids[2 + i * 2],
          left: bar.left / w,
          right: bar.right / w,
          top0: bar.numerator.top / h,
          bottom0: bar.denominator.bottom / h,
        ),
    ],
    signs: signs,
  );
}

/// Un número solo, centrado con aire: así no se deforma al llevarlo a 384×384.
img.Image _squareNumber(img.Image page, InkBox box) {
  final crop = _crop(page, (left: box.left, top: box.top, right: box.right - 1, bottom: box.bottom - 1), 4);
  final side = math.max(crop.width, crop.height) + 40;
  final square = img.Image(width: side, height: side);
  img.fill(square, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(square, crop, dstX: (side - crop.width) ~/ 2, dstY: (side - crop.height) ~/ 2);
  return square;
}

img.Image _crop(img.Image page, ({int left, int top, int right, int bottom}) box, int margin) {
  final x0 = (box.left - margin).clamp(0, page.width - 1), y0 = (box.top - margin).clamp(0, page.height - 1);
  final x1 = (box.right + margin).clamp(0, page.width - 1), y1 = (box.bottom + margin).clamp(0, page.height - 1);
  return img.copyCrop(page, x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1);
}

List<String> _loadVocabulary(String path) {
  final tokenizer = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return vocabularyFrom((tokenizer['model'] as Map<String, dynamic>)['vocab'] as Map<String, dynamic>);
}

Float32List _pixels(img.Image page) {
  const size = formulaImageSize;
  final square = img.copyResize(page, width: size, height: size, interpolation: img.Interpolation.cubic);
  final out = Float32List(3 * size * size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final p = square.getPixel(x, y);
      final i = y * size + x;
      out[i] = (p.r / 255 - 0.5) / 0.5;
      out[size * size + i] = (p.g / 255 - 0.5) / 0.5;
      out[2 * size * size + i] = (p.b / 255 - 0.5) / 0.5;
    }
  }
  return out;
}

/// La foto como la espera el modelo: solo la tinta sobre blanco (las líneas del
/// cuaderno, que son claras, lo confunden), sin lo que toca el borde (mesa,
/// sombra del marco). [box] es lo escrito: una fórmula chica se pierde si se
/// achica la hoja entera. null si no hay nada escrito.
({img.Image page, Uint8List ink, ({int left, int top, int right, int bottom}) box})? _prepare(String path) {
  final decoded = img.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) return null;
  var photo = img.bakeOrientation(decoded);
  if (photo.width > _maxSide || photo.height > _maxSide) {
    photo = photo.width >= photo.height
        ? img.copyResize(photo, width: _maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(photo, height: _maxSide, interpolation: img.Interpolation.average);
  }
  photo = photo.convert(numChannels: 3);
  final w = photo.width, h = photo.height;
  final clean = cleanPage(photo.getBytes(order: img.ChannelOrder.rgb), w, h, ScanFilter.byn);
  final raw = Uint8List(w * h);
  for (var i = 0; i < raw.length; i++) {
    raw[i] = clean[i * 3] < 128 ? 1 : 0;
  }
  final ink = dropBorderInk(raw, w, h, clean);
  final box = inkBounds(ink, w, h);
  if (box == null) return null;
  final page = img.Image.fromBytes(width: w, height: h, bytes: clean.buffer, numChannels: 3);
  return (page: page, ink: ink, box: box);
}

/// Quita la tinta que llega al borde de la foto, y la borra también de [clean]
/// (3 bytes por píxel), porque el modelo mira esa imagen.
Uint8List dropBorderInk(Uint8List ink, int w, int h, Uint8List clean) {
  final out = Uint8List.fromList(ink);
  final stack = <int>[];
  void visit(int i) {
    if (out[i] != 0) {
      out[i] = 0;
      stack.add(i);
    }
  }

  for (var x = 0; x < w; x++) {
    visit(x);
    visit((h - 1) * w + x);
  }
  for (var y = 0; y < h; y++) {
    visit(y * w);
    visit(y * w + w - 1);
  }
  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    clean[i * 3] = clean[i * 3 + 1] = clean[i * 3 + 2] = 255;
    final x = i % w;
    if (x > 0) visit(i - 1);
    if (x < w - 1) visit(i + 1);
    if (i >= w) visit(i - w);
    if (i < (h - 1) * w) visit(i + w);
  }
  return out;
}

/// El rectángulo de lo escrito; un punto suelto no cuenta. null si no hay nada.
({int left, int top, int right, int bottom})? inkBounds(Uint8List ink, int w, int h) {
  const minInk = 2;
  final rows = Int32List(h), cols = Int32List(w);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (ink[y * w + x] != 0) {
        rows[y]++;
        cols[x]++;
      }
    }
  }
  var top = 0, bottom = h - 1, left = 0, right = w - 1;
  while (top < h && rows[top] < minInk) {
    top++;
  }
  if (top == h) return null;
  while (rows[bottom] < minInk) {
    bottom--;
  }
  while (left < w && cols[left] < minInk) {
    left++;
  }
  if (left == w) return null;
  while (cols[right] < minInk) {
    right--;
  }
  return (left: left, top: top, right: right, bottom: bottom);
}
