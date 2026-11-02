import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'formula_engine.dart';

/// Lado mayor con que se aplana una foto: más que esto no agrega letra legible y
/// gasta mucha memoria.
const _maxSide = 2400;

/// Aplana la foto de una hoja arrugada con UVDoc y la guarda en [outPath]. Necesita
/// la foto directa: con la hoja ya recortada por el escáner casi no hace nada.
Future<void> unwarpPage(String photoPath, String modelPath, String outPath) => Isolate.run(() {
  final decoded = img.decodeImage(File(photoPath).readAsBytesSync());
  if (decoded == null) throw const FormatException('La foto no se pudo leer.');
  var photo = img.bakeOrientation(decoded);
  if (photo.width > _maxSide || photo.height > _maxSide) {
    photo = photo.width >= photo.height
        ? img.copyResize(photo, width: _maxSide, interpolation: img.Interpolation.average)
        : img.copyResize(photo, height: _maxSide, interpolation: img.Interpolation.average);
  }
  final out = runUnwarpModel(modelPath, imageToChannels(photo), photo.width, photo.height);
  final flat = channelsToImage(out.pixels, out.width, out.height);
  File(outPath).writeAsBytesSync(img.encodeJpg(flat, quality: 95));
});

/// La imagen por canales (todo el rojo, todo el verde, todo el azul), de 0 a 1.
Float32List imageToChannels(img.Image image) {
  final w = image.width, h = image.height;
  final out = Float32List(3 * w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = image.getPixel(x, y);
      final i = y * w + x;
      out[i] = p.r / 255;
      out[w * h + i] = p.g / 255;
      out[2 * w * h + i] = p.b / 255;
    }
  }
  return out;
}

/// Lo inverso de [imageToChannels].
img.Image channelsToImage(Float32List pixels, int w, int h) {
  final out = img.Image(width: w, height: h);
  int byte(double v) => (v * 255).round().clamp(0, 255);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = y * w + x;
      out.setPixelRgb(x, y, byte(pixels[i]), byte(pixels[w * h + i]), byte(pixels[2 * w * h + i]));
    }
  }
  return out;
}
