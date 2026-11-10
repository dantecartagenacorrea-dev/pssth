import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lector_pdf/domain/scan_filters.dart';

/// Hoja con sombra (más oscura a la derecha) y una "letra" negra al centro.
Uint8List _shadedPage(int w, int h) {
  final rgb = Uint8List(w * h * 3);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final paper = 210 - (x * 90 ~/ w); // de 210 a 120: sombra
      final ink = x > w * 0.4 && x < w * 0.45 && y > h * 0.3 && y < h * 0.7;
      final v = ink ? paper ~/ 4 : paper;
      final j = (y * w + x) * 3;
      rgb[j] = v + 10; // papel algo amarillento
      rgb[j + 1] = v + 5;
      rgb[j + 2] = v;
    }
  }
  return rgb;
}

int _at(Uint8List rgb, int w, int x, int y) => rgb[(y * w + x) * 3];

void main() {
  const w = 300, h = 400;
  final page = _shadedPage(w, h);

  test('B&N deja el papel blanco aun con sombra y la letra negra', () {
    final out = cleanPage(page, w, h, ScanFilter.byn);
    expect(_at(out, w, 20, 200), 255, reason: 'papel iluminado');
    expect(_at(out, w, 280, 200), 255, reason: 'papel en sombra');
    expect(_at(out, w, 128, 200), 0, reason: 'tinta');
  });

  test('Mejorar blanquea el papel y conserva la tinta oscura', () {
    final out = cleanPage(page, w, h, ScanFilter.mejorar);
    expect(_at(out, w, 280, 200), greaterThan(235));
    expect(_at(out, w, 128, 200), lessThan(60));
  });

  test('el filtro devuelve un JPEG del mismo tamaño', () async {
    final source = img.Image.fromBytes(width: w, height: h, bytes: page.buffer, numChannels: 3);
    final jpeg = Uint8List.fromList(img.encodeJpg(source));
    final r = await applyScanFilter(jpeg, ScanFilter.grises);
    expect((r.width, r.height), (w, h));
    expect(img.decodeJpg(r.jpeg), isNotNull);
    final same = await applyScanFilter(jpeg, ScanFilter.original);
    expect(same.jpeg, jpeg);
  });

  test('la calidad liviana achica y pesa menos; la alta no toca la página', () async {
    final big = img.Image(width: 3000, height: 2000);
    for (final p in big) {
      p
        ..r = (p.x * p.y) % 251
        ..g = (p.x + p.y) % 241
        ..b = p.x % 239;
    }
    final jpeg = Uint8List.fromList(img.encodeJpg(big, quality: 95));
    final page = (jpeg: jpeg, width: 3000, height: 2000);

    expect(identical(await compressScanPage(page, ScanQuality.alta), page), isTrue);

    final light = await compressScanPage(page, ScanQuality.liviana);
    expect((light.width, light.height), (1600, 1067));
    expect(light.jpeg.length, lessThan(jpeg.length));
  });
}
