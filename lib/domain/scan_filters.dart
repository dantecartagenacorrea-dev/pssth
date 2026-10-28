import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Cómo se limpia la foto de cada página antes de armar el PDF.
enum ScanFilter {
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

/// Lado mayor de la página limpia, en píxeles: unos 240 ppp en una hoja A4,
/// nítido para leer e imprimir sin que el PDF pese de más.
const _maxSide = 2400;

/// Aplica [filter] a la foto (JPEG) en segundo plano y devuelve el JPEG limpio
/// con su tamaño. Con [ScanFilter.original] devuelve la foto sin tocar.
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
  final w = image.width, h = image.height;
  final rgb = image.getBytes(order: img.ChannelOrder.rgb);
  final out = cleanPage(rgb, w, h, filter);
  final result = img.Image.fromBytes(width: w, height: h, bytes: out.buffer, numChannels: 3);
  return (jpeg: img.encodeJpg(result, quality: filter == ScanFilter.byn ? 80 : 85), width: w, height: h);
}

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
      case ScanFilter.byn:
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
