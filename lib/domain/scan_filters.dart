import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'form_page.dart';
import 'retype_ink.dart';
import 'scan_clean.dart';
import 'scanned_pdf.dart' show ScannedLine;

/// Cómo se limpia la foto de cada página antes de armar el PDF.
enum ScanFilter {
  /// Como una copia limpia: sin arrugas ni manchas y con los renglones parejos.
  limpio('Limpio'),

  /// Papel blanco y colores más vivos (sombras y tono amarillento fuera).
  mejorar('Mejorar'),

  /// Blanco y negro nítido: lo mejor para texto.
  byn('B&N'),

  /// Grises con el papel blanco.
  grises('Escala de grises'),

  /// La foto tal como salió del escáner.
  original('Original');

  const ScanFilter(this.label);
  final String label;
}

/// Cuánto pesa el PDF: a menos peso, menos detalle al ampliar o imprimir.
enum ScanQuality {
  alta('Alta', null, 0),
  media('Media', 2200, 75),
  liviana('Liviana', 1600, 60);

  const ScanQuality(this.label, this.maxSide, this.jpegQuality);
  final String label;

  /// Lado mayor en píxeles; null deja la página como está.
  final int? maxSide;
  final int jpegQuality;
}

/// La página limpia con el peso de [quality]. Nunca la agranda ni la deja más
/// pesada de lo que ya era.
Future<({Uint8List jpeg, int width, int height})> compressScanPage(
  ({Uint8List jpeg, int width, int height}) page,
  ScanQuality quality,
) async {
  final maxSide = quality.maxSide;
  if (maxSide == null) return page;
  return Isolate.run(() {
    final decoded = img.decodeJpg(page.jpeg);
    if (decoded == null) throw const FormatException('La página escaneada no es una imagen válida.');
    var image = decoded;
    if (math.max(image.width, image.height) > maxSide) {
      image = image.width >= image.height
          ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.average)
          : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.average);
    }
    final jpeg = img.encodeJpg(image, quality: quality.jpegQuality);
    if (jpeg.length >= page.jpeg.length) return page;
    return (jpeg: jpeg, width: image.width, height: image.height);
  });
}

/// Lado mayor de la página limpia, en píxeles: 4K (unos 330 ppp en una hoja
/// A4), nítido para ampliar e imprimir. Solo «Limpio» agranda las fotos más chicas.
const _maxSide = 3840;

/// Una foto más chica que esto no tiene detalle que rescatar: no se amplía.
const _minToEnlarge = 1000;

/// Aplica [filter] a la foto (JPEG) en segundo plano y devuelve el JPEG limpio
/// con su tamaño. Con [ScanFilter.original] devuelve la foto sin tocar.
/// Gira la foto de [path] un cuarto de vuelta a la derecha, en su mismo archivo.
Future<void> rotateScanFile(String path) => Isolate.run(() {
  final file = File(path);
  final decoded = img.decodeJpg(file.readAsBytesSync());
  if (decoded == null) throw const FormatException('La página escaneada no es una imagen válida.');
  file.writeAsBytesSync(img.encodeJpg(img.copyRotate(img.bakeOrientation(decoded), angle: 90), quality: 95));
});

/// La foto sin filtros, derecha y con peso medio, para guardarla como original.
Future<({Uint8List jpeg, int width, int height})> originalScanPage(String path) => Isolate.run(() {
  // decodeImage: una foto importada también puede ser PNG, WebP…
  final decoded = img.decodeImage(File(path).readAsBytesSync());
  if (decoded == null) throw const FormatException('La página escaneada no es una imagen válida.');
  var image = img.bakeOrientation(decoded);
  final maxSide = ScanQuality.media.maxSide!;
  if (math.max(image.width, image.height) > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: maxSide, interpolation: img.Interpolation.average);
  }
  return (
    jpeg: Uint8List.fromList(img.encodeJpg(image, quality: ScanQuality.media.jpegQuality)),
    width: image.width,
    height: image.height,
  );
});

/// Recorta la foto a un rectángulo dado en fracciones de la página.
Future<({Uint8List jpeg, int width, int height})> cropScanPage(
  Uint8List jpeg,
  ({double left, double top, double right, double bottom}) box,
) => Isolate.run(() {
  final decoded = img.decodeJpg(jpeg);
  if (decoded == null) throw const FormatException('La página escaneada no es una imagen válida.');
  final x = (box.left * decoded.width).floor(), y = (box.top * decoded.height).floor();
  final cropped = img.copyCrop(
    decoded,
    x: x,
    y: y,
    width: (box.right * decoded.width).ceil() - x,
    height: (box.bottom * decoded.height).ceil() - y,
  );
  return (jpeg: Uint8List.fromList(img.encodeJpg(cropped, quality: 90)), width: cropped.width, height: cropped.height);
});

/// Un filtro que deja menos de esto de lo que se ve en la foto no se usa: un
/// escáner puede dejar una mancha, nunca perder un dato.
const minContentKept = 0.9;

/// Ancho al que se comparan la foto y la página filtrada.
const _checkWidth = 1000;

/// Más oscuro que esta parte del promedio de alrededor es un trazo.
const _checkInk = 0.78;

/// Qué parte del contenido de la foto conserva la página filtrada (0 a 1): cada
/// trazo de la foto tiene que seguir ahí, aunque se haya corrido un poco al
/// enderezar. Una foto casi sin trazos da 1.
Future<double> contentKept(Uint8List photo, Uint8List filtered) => Isolate.run(() {
  final a = img.decodeJpg(photo), b = img.decodeJpg(filtered);
  if (a == null || b == null) return 1.0;
  final source = img.bakeOrientation(a);
  final w = math.min(_checkWidth, source.width);
  final h = (source.height * w / source.width).round();
  Uint8List lumOf(img.Image image) => _luminance(
    img
        .copyResize(image, width: w, height: h, interpolation: img.Interpolation.average)
        .convert(numChannels: 3)
        .getBytes(order: img.ChannelOrder.rgb),
    w * h,
  );
  final before = _strokes(lumOf(source), w, h);
  final after = _strokes(lumOf(b), w, h);
  // Las líneas de una tabla son poco al lado del texto: se cuentan aparte, para
  // que un filtro que borra la tabla entera no pase por bueno.
  final ruled = _ruledStrokes(before, w, h);
  var total = 0, kept = 0, lineTotal = 0, lineKept = 0;
  const reach = 2;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (before[y * w + x] == 0) continue;
      total++;
      final onLine = ruled[y * w + x] != 0;
      if (onLine) lineTotal++;
      var found = false;
      for (var dy = -reach; dy <= reach && !found; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (var dx = -reach; dx <= reach; dx++) {
          final xx = x + dx;
          if (xx >= 0 && xx < w && after[yy * w + xx] != 0) {
            found = true;
            break;
          }
        }
      }
      if (found) {
        kept++;
        if (onLine) lineKept++;
      }
    }
  }
  if (total < w * h * 0.002) return 1.0;
  final overall = kept / total;
  // Menos de media línea de ancho no es una tabla que medir.
  if (lineTotal < w / 2) return overall;
  return math.min(overall, lineKept / lineTotal);
});

/// Largo mínimo (fracción del lado) de un trazo recto para contarlo como línea.
const _lineRun = 0.08;

/// Trazos que forman parte de una línea recta larga, horizontal o vertical.
Uint8List _ruledStrokes(Uint8List strokes, int w, int h) {
  final out = Uint8List(w * h);
  void mark(int count, int length, int Function(int run, int at) index) {
    final minimum = (length * _lineRun).round();
    for (var run = 0; run < count; run++) {
      var start = -1, gap = 0;
      for (var at = 0; at <= length; at++) {
        final ink = at < length && strokes[index(run, at)] != 0;
        if (ink) {
          if (start < 0) start = at;
          gap = 0;
          continue;
        }
        // Un corte de un par de píxeles no parte la línea.
        if (start >= 0 && at < length && ++gap <= 2) continue;
        if (start >= 0 && at - gap - start >= minimum) {
          for (var k = start; k < at - gap; k++) {
            out[index(run, k)] = 1;
          }
        }
        start = -1;
        gap = 0;
      }
    }
  }

  mark(h, w, (y, x) => y * w + x);
  mark(w, h, (x, y) => y * w + x);
  return out;
}

/// Trazos: más oscuros que lo que los rodea (no importa si la hoja tiene sombras).
Uint8List _strokes(Uint8List lum, int w, int h) {
  final stride = w + 1;
  final sum = Int64List(stride * (h + 1));
  for (var y = 0; y < h; y++) {
    var row = 0;
    for (var x = 0; x < w; x++) {
      row += lum[y * w + x];
      sum[(y + 1) * stride + x + 1] = sum[y * stride + x + 1] + row;
    }
  }
  final r = math.max(4, w ~/ 60);
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final y0 = math.max(0, y - r), y1 = math.min(h, y + r + 1);
    for (var x = 0; x < w; x++) {
      final x0 = math.max(0, x - r), x1 = math.min(w, x + r + 1);
      final area = (y1 - y0) * (x1 - x0);
      final mean =
          (sum[y1 * stride + x1] - sum[y0 * stride + x1] - sum[y1 * stride + x0] + sum[y0 * stride + x0]) / area;
      if (lum[y * w + x] < mean * _checkInk) out[y * w + x] = 1;
    }
  }
  return out;
}

/// Copia chica de la foto para las miniaturas de los filtros.
Future<Uint8List> scanThumbnail(String path) => Isolate.run(() {
  final decoded = img.decodeJpg(File(path).readAsBytesSync());
  if (decoded == null) throw const FormatException('La página escaneada no es una imagen válida.');
  return img.encodeJpg(
    img.copyResize(img.bakeOrientation(decoded), height: 240, interpolation: img.Interpolation.average),
    quality: 85,
  );
});

Future<({Uint8List jpeg, int width, int height})> applyScanFilter(Uint8List jpeg, ScanFilter filter) =>
    Isolate.run(() => _apply(jpeg, filter));

({Uint8List jpeg, int width, int height}) _apply(Uint8List jpeg, ScanFilter filter) {
  final decoded = img.decodeJpg(jpeg);
  if (decoded == null) throw const FormatException('La página escaneada no es una imagen válida.');
  if (filter == ScanFilter.original) return (jpeg: jpeg, width: decoded.width, height: decoded.height);
  var image = img.bakeOrientation(decoded);
  final side = math.max(image.width, image.height);
  if (side > _maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: _maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: _maxSide, interpolation: img.Interpolation.average);
  }
  // «Limpio» se arma en 4K: al ampliar antes de limpiar, el borde de cada letra se
  // vuelve a definir y sale nítido, en vez de solo agrandar los píxeles.
  final longest = math.max(image.width, image.height);
  if (filter == ScanFilter.limpio && longest >= _minToEnlarge && longest < _maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: _maxSide, interpolation: img.Interpolation.linear)
        : img.copyResize(image, height: _maxSide, interpolation: img.Interpolation.linear);
  }
  final w = image.width, h = image.height;
  final rgb = image.getBytes(order: img.ChannelOrder.rgb);
  final out = filter == ScanFilter.limpio ? _cleanDocument(rgb, w, h) : cleanPage(rgb, w, h, filter);
  final result = img.Image.fromBytes(width: w, height: h, bytes: out.buffer, numChannels: 3);
  return (
    jpeg: img.encodeJpg(result, quality: filter == ScanFilter.limpio ? 92 : (filter == ScanFilter.byn ? 85 : 90)),
    width: w,
    height: h,
  );
}

Uint8List _cleanDocument(Uint8List rgb, int w, int h) {
  final lum = _luminance(rgb, w * h);
  return cleanDocumentColor(rgb, lum, _paperBrightness(lum, w, h), w, h);
}

Uint8List _luminance(Uint8List rgb, int n) {
  final lum = Uint8List(n);
  for (var i = 0, j = 0; i < n; i++, j += 3) {
    lum[i] = (rgb[j] * 299 + rgb[j + 1] * 587 + rgb[j + 2] * 114) ~/ 1000;
  }
  return lum;
}

/// Mide en la foto las negritas de [lines] y recorta las firmas y los sellos.
Future<PageInk> readInk(String path, List<ScannedLine> lines) => Isolate.run(() {
  final decoded = img.decodeJpg(File(path).readAsBytesSync());
  if (decoded == null) return noInk;
  final image = img.bakeOrientation(decoded).convert(numChannels: 3);
  final w = image.width, h = image.height;
  final rgb = image.getBytes(order: img.ChannelOrder.rgb);
  final lum = _luminance(rgb, w * h);
  return readPageInk(rgb, lum, _paperBrightness(lum, w, h), w, h, lines);
});

/// Las líneas de la hoja y lo que no es texto, para rearmarla con su formato.
Future<FormPageLayer> readFormLayer(String path, List<ScannedLine> lines, List<PageMark> marks) => Isolate.run(() {
  final decoded = img.decodeJpg(File(path).readAsBytesSync());
  if (decoded == null) throw const FormatException('La página escaneada no es una imagen válida.');
  var image = img.bakeOrientation(decoded);
  if (image.width > 2000) image = img.copyResize(image, width: 2000, interpolation: img.Interpolation.average);
  final w = image.width, h = image.height;
  final lum = _luminance(image.convert(numChannels: 3).getBytes(order: img.ChannelOrder.rgb), w * h);
  final layer = formLayerFrom(lum, _paperBrightness(lum, w, h), w, h, lines, marks);
  if (layer.blank) return (jpeg: null, rules: layer.rules, tilt: layer.tilt);
  final gray = img.Image.fromBytes(width: w, height: h, bytes: layer.gray.buffer, numChannels: 1);
  return (jpeg: img.encodeJpg(gray.convert(numChannels: 3), quality: 85), rules: layer.rules, tilt: layer.tilt);
});

/// La foto en un tamaño que la IA de la computadora lee bien y rápido.
Future<Uint8List> photoForAi(String path) => Isolate.run(() {
  final decoded = img.decodeJpg(File(path).readAsBytesSync());
  if (decoded == null) throw const FormatException('La página escaneada no es una imagen válida.');
  var image = img.bakeOrientation(decoded);
  const longest = 1733;
  if (math.max(image.width, image.height) > longest) {
    image = image.height >= image.width
        ? img.copyResize(image, height: longest, interpolation: img.Interpolation.average)
        : img.copyResize(image, width: longest, interpolation: img.Interpolation.average);
  }
  return img.encodeJpg(image, quality: 90);
});

/// Debajo de esto una página se ve borrosa: conviene repetirla.
const blurryBelow = 0.08;

/// Qué tan nítida salió una foto (ver [pageSharpness]).
Future<double> scanSharpness(String path) => Isolate.run(() {
  final decoded = img.decodeJpg(File(path).readAsBytesSync());
  if (decoded == null) return 1.0;
  var image = img.bakeOrientation(decoded);
  if (image.width > 1700) image = img.copyResize(image, width: 1700, interpolation: img.Interpolation.average);
  final w = image.width, h = image.height;
  final lum = _luminance(image.convert(numChannels: 3).getBytes(order: img.ChannelOrder.rgb), w * h);
  return pageSharpness(lum, _paperBrightness(lum, w, h), w, h);
});

/// Limpia una página en RGB (3 bytes por píxel). El brillo del papel se mide
/// por zonas y se lleva a blanco: así se van las sombras y el tono de la luz.
Uint8List cleanPage(Uint8List rgb, int w, int h, ScanFilter filter) {
  final n = w * h;
  final lum = Uint8List(n);
  for (var i = 0, j = 0; i < n; i++, j += 3) {
    lum[i] = (rgb[j] * 299 + rgb[j + 1] * 587 + rgb[j + 2] * 114) ~/ 1000;
  }
  final bg = _paperBrightness(lum, w, h);
  final out = Uint8List(n * 3);
  for (var i = 0, j = 0; i < n; i++, j += 3) {
    final paper = math.max(bg[i], 40);
    switch (filter) {
      case ScanFilter.byn || ScanFilter.limpio:
        // Oscuro respecto del papel → negro; el resto → blanco, con un borde
        // suave para que las letras no se vean dentadas.
        final v = _ramp(lum[i] * 255 ~/ paper, 120, 190);
        out[j] = out[j + 1] = out[j + 2] = v;
      case ScanFilter.grises:
        final v = _contrast(math.min(255, lum[i] * 255 ~/ paper));
        out[j] = out[j + 1] = out[j + 2] = v;
      case ScanFilter.mejorar:
        for (var c = 0; c < 3; c++) {
          out[j + c] = _contrast(math.min(255, rgb[j + c] * 255 ~/ paper));
        }
      case ScanFilter.original:
        out[j] = rgb[j];
        out[j + 1] = rgb[j + 1];
        out[j + 2] = rgb[j + 2];
    }
  }
  return out;
}

/// Brillo del papel en cada píxel: el máximo de cada bloque (el papel es lo
/// más claro; las letras son finas), suavizado e interpolado a todo el tamaño.
Uint8List _paperBrightness(Uint8List lum, int w, int h) {
  const block = 24;
  final bw = (w + block - 1) ~/ block, bh = (h + block - 1) ~/ block;
  final grid = Float64List(bw * bh);
  for (var by = 0; by < bh; by++) {
    for (var bx = 0; bx < bw; bx++) {
      var m = 0;
      final y1 = math.min(h, (by + 1) * block), x1 = math.min(w, (bx + 1) * block);
      for (var y = by * block; y < y1; y++) {
        final row = y * w;
        for (var x = bx * block; x < x1; x++) {
          final v = lum[row + x];
          if (v > m) m = v;
        }
      }
      grid[by * bw + bx] = m.toDouble();
    }
  }
  // Suavizado 3×3 dos veces: el papel cambia de brillo despacio.
  var g = grid;
  for (var pass = 0; pass < 2; pass++) {
    final next = Float64List(bw * bh);
    for (var y = 0; y < bh; y++) {
      for (var x = 0; x < bw; x++) {
        var sum = 0.0, count = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final yy = y + dy, xx = x + dx;
            if (yy < 0 || yy >= bh || xx < 0 || xx >= bw) continue;
            sum += g[yy * bw + xx];
            count++;
          }
        }
        next[y * bw + x] = sum / count;
      }
    }
    g = next;
  }
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    final fy = math.min(bh - 1.0, math.max(0.0, (y + 0.5) / block - 0.5));
    final y0 = fy.floor(), y1 = math.min(bh - 1, y0 + 1), ty = fy - y0;
    for (var x = 0; x < w; x++) {
      final fx = math.min(bw - 1.0, math.max(0.0, (x + 0.5) / block - 0.5));
      final x0 = fx.floor(), x1 = math.min(bw - 1, x0 + 1), tx = fx - x0;
      final top = g[y0 * bw + x0] * (1 - tx) + g[y0 * bw + x1] * tx;
      final bottom = g[y1 * bw + x0] * (1 - tx) + g[y1 * bw + x1] * tx;
      out[y * w + x] = (top * (1 - ty) + bottom * ty).round().clamp(0, 255);
    }
  }
  return out;
}

int _ramp(int v, int dark, int light) {
  if (v <= dark) return 0;
  if (v >= light) return 255;
  final t = (v - dark) / (light - dark);
  return (255 * t * t * (3 - 2 * t)).round();
}

/// Más contraste: los grises claros se van a blanco, la tinta se oscurece.
int _contrast(int v) => (((v - 40) * 255) ~/ 195).clamp(0, 255);
