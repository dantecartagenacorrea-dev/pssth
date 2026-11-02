import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../domain/math/fraction_bars.dart';
import '../domain/math/stacked_math.dart';
import '../domain/scan_filters.dart';
import 'native_text.dart';

const _maxSide = 1600;
const _maxFractions = 8;

/// Dos tamaños para mostrarle el número al lector: si con uno se confunde, a
/// veces con el otro no.
const _renderings = [(height: 96, gap: 30, margin: 120), (height: 160, gap: 90, margin: 120)];

typedef _Prepared = ({
  List<String> numerator,
  List<String> denominator,
  double left,
  double right,
  double top,
  double bottom,
});

/// Un signo reconocido entre dos fracciones ([from] y [to]: el hueco entre ellas).
typedef _Sign = ({String text, double x, double y, double from, double to});

/// Lee una cuenta con fracciones apiladas de una foto: el lector de texto se
/// salta los números sueltos, así que se busca la raya de cada fracción y lo de
/// arriba y lo de abajo se le muestra aparte, repetido en un renglón. null si
/// no hay fracciones o alguna cifra no se lee con seguridad.
Future<String?> readStackedFractions(String path, NativeText native) async {
  final dir = await getTemporaryDirectory();
  final List<_Prepared> prepared;
  final List<_Sign> signs;
  try {
    final tempPath = dir.path;
    (prepared, signs) = await Isolate.run(() => _prepare(path, tempPath));
  } on FileSystemException {
    return null;
  }
  if (prepared.isEmpty) return null;
  try {
    final fractions = <ReadFraction>[];
    for (final p in prepared) {
      final top = await _readNumber(native, p.numerator);
      final bottom = await _readNumber(native, p.denominator);
      if (top == null || bottom == null) return null;
      fractions.add((text: '$top/$bottom', left: p.left, right: p.right, top: p.top, bottom: p.bottom));
    }
    // El signo que se ve en la imagen manda sobre lo que el lector creyó ver ahí.
    final read = (await native.recognizeLines(path)).lines;
    return assembleFractions(fractions, [
      for (final line in read)
        if (!signs.any((s) => line.left + line.width / 2 >= s.from && line.left + line.width / 2 <= s.to)) line,
      for (final s in signs) (text: s.text, left: s.x, top: s.y, width: 0.001, height: 0.001),
    ]);
  } finally {
    for (final p in prepared) {
      for (final temp in [...p.numerator, ...p.denominator]) {
        try {
          await File(temp).delete();
        } on FileSystemException {
          // son temporales: si no se borran, no pasa nada
        }
      }
    }
  }
}

Future<String?> _readNumber(NativeText native, List<String> images) async {
  for (final path in images) {
    final number = digitsFromRepeat(await native.recognize(path, languageCorrection: false, minimumTextHeight: 0.01));
    if (number != null) return number;
  }
  return null;
}

/// Busca las fracciones y deja una imagen por cada número.
(List<_Prepared>, List<_Sign>) _prepare(String path, String dir) {
  final decoded = img.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) return (const [], const []);
  var photo = img.bakeOrientation(decoded);
  if (math.max(photo.width, photo.height) > _maxSide) {
    photo = photo.width >= photo.height
        ? img.copyResize(photo, width: _maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(photo, height: _maxSide, interpolation: img.Interpolation.average);
  }
  final w = photo.width, h = photo.height;
  final clean = cleanPage(photo.convert(numChannels: 3).getBytes(order: img.ChannelOrder.rgb), w, h, ScanFilter.byn);
  final dark = Uint8List(w * h);
  for (var i = 0; i < dark.length; i++) {
    dark[i] = clean[i * 3] < 128 ? 1 : 0;
  }
  final bars = findFractionBars(dark, w, h);
  if (bars.isEmpty || bars.length > _maxFractions) return (const [], const []);
  final page = img.Image.fromBytes(width: w, height: h, bytes: clean.buffer, numChannels: 3);
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final signs = <_Sign>[
    for (var i = 1; i < bars.length; i++)
      if (classifyOperator(dark, w, (
            left: bars[i - 1].right + 2,
            top: math.min(bars[i - 1].numerator.top, bars[i].numerator.top),
            right: bars[i].left - 2,
            bottom: math.max(bars[i - 1].denominator.bottom, bars[i].denominator.bottom),
          ))
          case final sign?)
        (
          text: sign,
          x: (bars[i - 1].right + bars[i].left) / 2 / w,
          y: bars[i].y / h,
          from: bars[i - 1].right / w,
          to: bars[i].left / w,
        ),
  ];
  final fractions = [
    for (final (i, bar) in bars.indexed)
      (
        numerator: _saveRepeated(page, bar.numerator, '$dir/fraccion_${stamp}_${i}_a'),
        denominator: _saveRepeated(page, bar.denominator, '$dir/fraccion_${stamp}_${i}_b'),
        left: bar.left / w,
        right: bar.right / w,
        top: bar.numerator.top / h,
        bottom: bar.denominator.bottom / h,
      ),
  ];
  return (fractions, signs);
}

/// El número repetido tres veces en un renglón, como texto común: así el lector
/// lo reconoce, y si las tres copias coinciden se puede confiar.
List<String> _saveRepeated(img.Image page, InkBox box, String name) {
  final crop = img.copyCrop(page, x: box.left, y: box.top, width: box.right - box.left, height: box.bottom - box.top);
  return [for (final (i, r) in _renderings.indexed) _saveStrip(crop, r.height, r.gap, r.margin, '${name}_$i.jpg')];
}

String _saveStrip(img.Image crop, int height, int gap, int margin, String out) {
  final digit = img.copyResize(crop, height: height, interpolation: img.Interpolation.average);
  final strip = img.Image(width: digit.width * 3 + gap * 2 + margin * 2, height: height + margin * 2);
  img.fill(strip, color: img.ColorRgb8(255, 255, 255));
  for (var i = 0; i < 3; i++) {
    img.compositeImage(strip, digit, dstX: margin + i * (digit.width + gap), dstY: margin);
  }
  File(out).writeAsBytesSync(img.encodeJpg(strip, quality: 95));
  return out;
}
