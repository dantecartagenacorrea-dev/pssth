import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/form_page.dart';
import 'package:lector_pdf/domain/retype_ink.dart';
import 'package:lector_pdf/domain/scanned_pdf.dart';

const _w = 1000, _h = 1400;

Uint8List _blank() => Uint8List(_w * _h)..fillRange(0, _w * _h, 255);
Uint8List _paper() => Uint8List(_w * _h)..fillRange(0, _w * _h, 255);

void _fill(Uint8List lum, int x0, int y0, int x1, int y1, {int value = 0}) {
  for (var y = y0; y < y1; y++) {
    lum.fillRange(y * _w + x0, y * _w + x1, value);
  }
}

/// Casilla hueca, como las de un formulario.
void _box(Uint8List lum, int x, int y, int side) {
  _fill(lum, x, y, x + side, y + 3);
  _fill(lum, x, y + side - 3, x + side, y + side);
  _fill(lum, x, y, x + 3, y + side);
  _fill(lum, x + side - 3, y, x + side, y + side);
}

void main() {
  test('encuentra las líneas horizontales y verticales de una tabla', () {
    final lum = _blank();
    _fill(lum, 100, 300, 900, 303);
    _fill(lum, 100, 600, 900, 603);
    _fill(lum, 100, 300, 103, 603);
    final layer = formLayerFrom(lum, _paper(), _w, _h, const [], const []);
    final horizontal = layer.rules.where((r) => r.y0 == r.y1).toList();
    final vertical = layer.rules.where((r) => r.x0 == r.x1).toList();
    expect(horizontal, hasLength(2));
    expect(vertical, hasLength(1));
    expect(horizontal.first.x0, closeTo(0.1, 0.005));
    expect(horizontal.first.x1, closeTo(0.9, 0.005));
    expect(layer.blank, isTrue, reason: 'lo que se redibuja no queda también en la capa');
  });

  test('las esquinas de una tabla cierran justas, sin puntitas', () {
    final lum = _blank();
    _fill(lum, 100, 300, 906, 303);
    _fill(lum, 900, 295, 903, 600);
    final rules = formLayerFrom(lum, _paper(), _w, _h, const [], const []).rules;
    final horizontal = rules.firstWhere((r) => r.y0 == r.y1);
    final vertical = rules.firstWhere((r) => r.x0 == r.x1);
    expect(horizontal.x1, vertical.x0);
    expect(vertical.y0, horizontal.y0);
  });

  test('una línea algo torcida sale como una sola, recta', () {
    final lum = _blank();
    for (var x = 100; x < 900; x++) {
      final y = 500 + (x - 100) ~/ 100;
      _fill(lum, x, y, x + 1, y + 3);
    }
    final rules = formLayerFrom(lum, _paper(), _w, _h, const [], const []).rules;
    expect(rules, hasLength(1));
    expect(rules.single.y0, rules.single.y1);
  });

  test('una hoja torcida se nivela: dos líneas paralelas no cambian de distancia', () {
    final lum = _blank();
    for (var x = 100; x < 900; x++) {
      final drop = (x - 100) ~/ 100;
      _fill(lum, x, 500 + drop, x + 1, 503 + drop);
      _fill(lum, x, 800 + drop, x + 1, 803 + drop);
    }
    final layer = formLayerFrom(lum, _paper(), _w, _h, const [], const []);
    expect(layer.tilt, closeTo(0.01 * _w / _h, 0.002));
    expect(layer.rules[1].y0 - layer.rules[0].y0, closeTo(300 / _h, 0.002));
  });

  test('también nivela una foto bien torcida', () {
    final lum = _blank();
    for (var x = 100; x < 900; x++) {
      final y = 500 + (x - 100) * 5 ~/ 100;
      _fill(lum, x, y, x + 1, y + 3);
    }
    expect(formLayerFrom(lum, _paper(), _w, _h, const [], const []).tilt, closeTo(0.05 * _w / _h, 0.005));
  });

  test('lo que se pidió sacar no queda en la capa de fondo', () {
    final lum = _blank();
    _box(lum, 300, 900, 120);
    final mark = (jpeg: Uint8List(0), left: 0.29, top: 890 / _h, boxWidth: 0.14, boxHeight: 140 / _h);
    expect(formLayerFrom(lum, _paper(), _w, _h, const [], [mark]).blank, isTrue);
  });

  test('una casilla se mueve junto con la hoja al nivelar', () {
    final lum = _blank();
    for (var x = 100; x < 900; x++) {
      _fill(lum, x, 500 + (x - 100) ~/ 50, x + 1, 503 + (x - 100) ~/ 50);
    }
    _box(lum, 880, 300, 28);
    final layer = formLayerFrom(lum, _paper(), _w, _h, const [], const []);
    // A la derecha del centro la hoja bajaba: la casilla sube unos 8 píxeles.
    expect(layer.gray[(300 - 8) * _w + 890], lessThan(100));
    expect(layer.gray[(300 + 1) * _w + 890], 255);
  });

  test('una casilla queda donde estaba y no se toma por línea', () {
    final lum = _blank();
    _box(lum, 200, 200, 28);
    final layer = formLayerFrom(lum, _paper(), _w, _h, const [], const []);
    expect(layer.rules, isEmpty);
    expect(layer.gray[200 * _w + 210], lessThan(100));
  });

  test('el texto leído se saca de la capa, porque se escribe de nuevo', () {
    final lum = _blank();
    _fill(lum, 200, 400, 500, 430);
    const line = (text: 'Nombre', left: 0.2, top: 400 / _h, width: 0.3, height: 30 / _h);
    final layer = formLayerFrom(lum, _paper(), _w, _h, const [line], const []);
    expect(layer.gray[415 * _w + 300], 255);
  });

  test('un trazo de letra dentro de un renglón no es una línea', () {
    final lum = _blank();
    _fill(lum, 200, 412, 500, 415);
    const line = (text: 'TÍTULO', left: 0.2, top: 400 / _h, width: 0.3, height: 30 / _h);
    expect(formLayerFrom(lum, _paper(), _w, _h, const [line], const []).rules, isEmpty);
  });

  const row1 = (text: 'renglón uno', left: 0.1, top: 400 / _h, width: 0.8, height: 30 / _h);
  const row2 = (text: 'renglón dos', left: 0.1, top: 436 / _h, width: 0.8, height: 30 / _h);

  test('letras alineadas de dos renglones no son una línea', () {
    final lum = _blank();
    _fill(lum, 500, 410, 503, 460);
    expect(formLayerFrom(lum, _paper(), _w, _h, const [row1, row2], const []).rules, isEmpty);
  });

  test('un divisor largo de tabla se queda aunque cruce texto', () {
    final lum = _blank();
    _fill(lum, 100, 300, 900, 303);
    _fill(lum, 500, 300, 503, 800);
    final rules = formLayerFrom(lum, _paper(), _w, _h, const [row1, row2], const []).rules;
    expect(rules.where((r) => r.x0 == r.x1), hasLength(1));
  });

  test('la sombra punteada del borde del papel no queda en el fondo', () {
    final lum = _blank();
    for (var y = 300; y < 900; y += 20) {
      _fill(lum, 30, y, 36, y + 8);
    }
    const line = (text: 'Texto del cuerpo', left: 0.2, top: 0.3, width: 0.6, height: 0.02);
    expect(formLayerFrom(lum, _paper(), _w, _h, const [line], const []).blank, isTrue);
  });

  test('una casilla al costado del texto se queda', () {
    final lum = _blank();
    _box(lum, 820, 600, 28);
    const line = (text: 'Texto del cuerpo', left: 0.2, top: 0.3, width: 0.6, height: 0.02);
    expect(formLayerFrom(lum, _paper(), _w, _h, const [line], const []).blank, isFalse);
  });

  test('muchas rayas muy juntas son una trama, no líneas de formulario', () {
    final lum = _blank();
    _fill(lum, 100, 300, 900, 303);
    for (var x = 200; x < 300; x += 6) {
      _fill(lum, x, 300, x + 2, 800);
    }
    final rules = formLayerFrom(lum, _paper(), _w, _h, const [], const []).rules;
    expect(rules.where((r) => r.x0 == r.x1), isEmpty);
    expect(rules.where((r) => r.y0 == r.y1), hasLength(1), reason: 'la línea de verdad se queda');
  });

  test('dos rayas casi encimadas se dibujan como una', () {
    final lum = _blank();
    _fill(lum, 100, 500, 900, 503);
    _fill(lum, 100, 508, 700, 511);
    expect(formLayerFrom(lum, _paper(), _w, _h, const [], const []).rules, hasLength(1));
  });

  test('las líneas de un cuaderno rayado se quedan todas', () {
    final lum = _blank();
    for (var y = 300; y < 900; y += 42) {
      _fill(lum, 100, y, 900, y + 2);
    }
    expect(formLayerFrom(lum, _paper(), _w, _h, const [], const []).rules, hasLength(15));
  });

  /// Una trama de rayas muy juntas, como el muaré de una pantalla fotografiada.
  void trama(Uint8List lum) {
    for (var x = 750; x < 850; x += 6) {
      _fill(lum, x, 1000, x + 2, 1300);
    }
  }

  test('con trama, una raya que cuelga de una línea hacia el vacío no es del formulario', () {
    final lum = _blank();
    trama(lum);
    _fill(lum, 100, 300, 900, 303);
    _fill(lum, 100, 600, 900, 603);
    _fill(lum, 500, 300, 503, 603);
    _fill(lum, 300, 600, 303, 900);
    final vertical = formLayerFrom(lum, _paper(), _w, _h, const [], const []).rules.where((r) => r.x0 == r.x1);
    expect(vertical, hasLength(1));
    expect(vertical.single.x0, closeTo(0.5, 0.01));
  });

  test('sin trama, una raya que baja de una línea se queda (esquina en L)', () {
    final lum = _blank();
    _fill(lum, 100, 600, 900, 603);
    _fill(lum, 300, 600, 303, 900);
    expect(formLayerFrom(lum, _paper(), _w, _h, const [], const []).rules.where((r) => r.x0 == r.x1), hasLength(1));
  });

  test('con trama, los puntitos sueltos no quedan; una casilla sí', () {
    final lum = _blank();
    trama(lum);
    for (var y = 300; y < 900; y += 40) {
      for (var x = 300; x < 700; x += 40) {
        _fill(lum, x, y, x + 3, y + 3);
      }
    }
    expect(formLayerFrom(lum, _paper(), _w, _h, const [], const []).blank, isTrue);
    _box(lum, 200, 1000, 28);
    expect(formLayerFrom(lum, _paper(), _w, _h, const [], const []).blank, isFalse);
  });

  test('una línea gris fina repartida entre dos filas también se encuentra', () {
    final lum = _blank();
    // Cada fila apenas gris: ninguna sola es tinta, juntas son una línea.
    _fill(lum, 100, 500, 900, 501, value: 200);
    _fill(lum, 100, 501, 900, 502, value: 200);
    final rules = formLayerFrom(lum, _paper(), _w, _h, const [], const []).rules;
    expect(rules, hasLength(1));
    expect(rules.single.weight * _h, lessThanOrEqualTo(1.5), reason: 'fina, como en el original');
  });

  test('el borde de letras grises dentro de un renglón no se vuelve línea', () {
    final lum = _blank();
    _fill(lum, 200, 410, 700, 411, value: 200);
    _fill(lum, 200, 411, 700, 412, value: 200);
    const line = (text: 'PERSONAL INFORMATION', left: 0.2, top: 405 / _h, width: 0.5, height: 25 / _h);
    expect(formLayerFrom(lum, _paper(), _w, _h, const [line], const []).rules, isEmpty);
  });

  test('una raya vertical suelta es el borde del papel, no una línea', () {
    final lum = _blank();
    _fill(lum, 60, 300, 63, 700);
    final layer = formLayerFrom(lum, _paper(), _w, _h, const [], const []);
    expect(layer.rules, isEmpty);
    expect(layer.blank, isTrue, reason: 'tampoco queda en la capa de fondo');
  });

  test('un resto muy claro no queda en la capa de fondo', () {
    final lum = _blank();
    _fill(lum, 300, 900, 500, 1100, value: 222);
    expect(formLayerFrom(lum, _paper(), _w, _h, const [], const []).blank, isTrue);
  });

  test('una mancha gruesa no es una línea', () {
    final lum = _blank();
    _fill(lum, 100, 700, 900, 760);
    expect(formLayerFrom(lum, _paper(), _w, _h, const [], const []).rules, isEmpty);
  });

  final jpeg = base64Decode(
    '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=',
  );

  test('el PDF lleva el texto visible y las líneas, sin la foto', () async {
    final page = (
      jpeg: jpeg,
      width: 1000,
      height: 1400,
      lines: const [(text: 'Nombre:', left: 0.1, top: 0.1, width: 0.2, height: 0.02)],
    );
    final raw = latin1.decode(
      await buildFormPdf([
        (
          page: page,
          ink: noInk,
          layer: (jpeg: null, rules: const [(x0: 0.1, y0: 0.2, x1: 0.9, y1: 0.2, weight: 0.002)], tilt: 0.0),
        ),
      ], compress: false),
    );
    expect(raw, contains('Nombre:'));
    expect(raw, isNot(contains('3 Tr')), reason: 'el texto se ve');
    expect(raw, isNot(matches(RegExp(r'/Subtype\s*/Image'))));
    expect(raw, matches(RegExp(r'\bS\b')), reason: 'línea trazada');
  });

  Future<String> pdfOf(List<ScannedLine> lines) async => latin1.decode(
    await buildFormPdf([
      (
        page: (jpeg: jpeg, width: 1000, height: 1400, lines: lines),
        ink: noInk,
        layer: (jpeg: null, rules: const <FormRule>[], tilt: 0.0),
      ),
    ], compress: false),
  );

  List<String> sizesOf(String raw) => RegExp(r'/F\d+ ([\d.]+) Tf').allMatches(raw).map((m) => m[1]!).toSet().toList();

  test('renglones del cuerpo con medidas algo distintas llevan la misma letra', () async {
    final raw = await pdfOf(const [
      (text: 'uno dos tres', left: 0.1, top: 0.1, width: 0.5, height: 0.018),
      (text: 'cuatro cinco seis', left: 0.1, top: 0.15, width: 0.7, height: 0.021),
      (text: 'siete ocho nueve', left: 0.1, top: 0.2, width: 0.7, height: 0.019),
    ]);
    expect(sizesOf(raw), hasLength(1));
  });

  test('un título mucho más grande conserva su tamaño', () async {
    final raw = await pdfOf(const [
      (text: 'TITULO', left: 0.1, top: 0.05, width: 0.6, height: 0.06),
      (text: 'uno dos tres', left: 0.1, top: 0.15, width: 0.5, height: 0.018),
      (text: 'cuatro cinco seis', left: 0.1, top: 0.2, width: 0.7, height: 0.018),
    ]);
    expect(sizesOf(raw).length, greaterThan(1));
  });

  test('una hoja sin texto va con su foto', () async {
    final page = (jpeg: jpeg, width: 1000, height: 1400, lines: const <ScannedLine>[]);
    final raw = latin1.decode(
      await buildFormPdf([
        (page: page, ink: noInk, layer: (jpeg: null, rules: const <FormRule>[], tilt: 0.0)),
      ], compress: false),
    );
    expect(raw, matches(RegExp(r'/Subtype\s*/Image')));
  });
}
