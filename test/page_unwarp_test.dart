import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:lector_pdf/platform/page_unwarp.dart';

void main() {
  test('una imagen pasa a canales y vuelve igual', () {
    final image = img.Image(width: 3, height: 2);
    image.setPixelRgb(0, 0, 255, 0, 0);
    image.setPixelRgb(2, 1, 10, 200, 30);
    final channels = imageToChannels(image);
    expect(channels.length, 18);
    expect(channels[0], 1, reason: 'el rojo va primero');
    final back = channelsToImage(channels, 3, 2);
    final p = back.getPixel(2, 1);
    expect((p.r, p.g, p.b), (10, 200, 30));
  });

  test('un valor fuera de rango no da la vuelta', () {
    final out = channelsToImage(imageToChannels(img.Image(width: 1, height: 1))..[0] = 1.4, 1, 1);
    expect(out.getPixel(0, 0).r, 255);
  });
}
