import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/scanned_pdf.dart';
import 'package:lector_pdf/domain/spanish_words.dart';

ScannedLine _at(String text) => (text: text, left: 0.1, top: 0.1, width: 0.8, height: 0.02);

void main() {
  final words = SpanishWords(File('assets/words/spanish_words.bin').readAsBytesSync());

  ({List<String> texts, Set<int> doubts}) check(List<String> lines) {
    final r = checkSpelling([for (final l in lines) _at(l)], words);
    return (texts: [for (final l in r.lines) l.text], doubts: r.doubts);
  }

  test('la lista conoce el español y no lo inventado', () {
    for (final w in ['pedir', 'policia', 'denuncia', 'año', 'ano', 'sindicados']) {
      expect(words.contains(w), isTrue, reason: w);
    }
    for (final w in ['pecir', 'feha', 'contormes', 'xqzw', 'agresionez']) {
      expect(words.contains(w), isFalse, reason: w);
    }
  });

  test('arregla los errores típicos del lector y deja el renglón para mirar', () {
    final r = check(['fue a pecir el auxilio', 'en horas de la feha', 'la casa de ml primo']);
    expect(r.texts, ['fue a pedir el auxilio', 'en horas de la fecha', 'la casa de mi primo']);
    expect(r.doubts, {0, 1, 2});
  });

  test('con dos palabras posibles no elige: «contormes» puede ser conformes o contornes', () {
    final r = check(['no contormes con ello']);
    expect(r.texts.single, 'no contormes con ello');
    expect(r.doubts, {0});
  });

  test('letras y números cruzados', () {
    final r = check(['de 1as partes y n0 de otras', 'esta es la primera hoja']);
    expect(r.texts.first, 'de las partes y no de otras');
    expect(r.doubts, {0});
  });

  test('una mayúscula suelta se corrige sin marcar', () {
    final r = check(['cuando estoS se hicieron presentes', 'placa de circulaciön']);
    expect(r.texts, ['cuando estos se hicieron presentes', 'placa de circulación']);
    expect(r.doubts, isEmpty);
  });

  test('lo correcto no se toca ni se marca, con o sin tilde', () {
    const lines = [
      'Por todo lo expuesto de conformidad al Art. 284 y Art. 285 del CPP formulo',
      'placa de circulación 1234ABC, solicitando a su autoridad',
      'razon de la policia en el año 2020',
      'JUAN PEREZ con C.I. 1234567 LP. y Doña Ramírez Quispe',
    ];
    final r = check(lines);
    expect(r.texts, lines);
    expect(r.doubts, isEmpty);
  });

  test('si no se sabe cuál es, no se cambia: solo se marca', () {
    final r = check(['esto es una xqzw de la hoja que se ve bien']);
    expect(r.texts.single, contains('xqzw'));
    expect(r.doubts, {0});
  });

  test('una palabra cortada al final del renglón no se marca', () {
    final r = check(['proceda al desdobla-', 'miento y captura del sindicado']);
    expect(r.texts, ['proceda al desdobla-', 'miento y captura del sindicado']);
    expect(r.doubts, isEmpty);
  });

  test('una hoja en otro idioma no se toca', () {
    const lines = ['the quick brown fox jumps over the lazy dog', 'this sheet should stay exactly as it reads'];
    final r = check(lines);
    expect(r.texts, lines);
    expect(r.doubts, isEmpty);
  });

  test('sin texto no pasa nada', () {
    expect(check(const []).texts, isEmpty);
  });
}
