import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/read_lines_align.dart';
import 'package:lector_pdf/domain/scanned_pdf.dart';

ScannedLine _at(String text, double top, {double left = 0.1}) =>
    (text: text, left: left, top: top, width: 0.8, height: 0.02);

void main() {
  test('el texto es de la IA y el lugar, del lector común', () {
    final r = alignReadLines(
      ['razón por la cual tuve que encerrarme', 'sufrir más agresiones, no conformes'],
      [_at('sufrir mas agresiones, n0 conformes', 0.3, left: 0.2), _at('raz?n por la cual tuve que encerrarrme', 0.2)],
    );
    expect(r.lines.first.text, 'razón por la cual tuve que encerrarme');
    expect(r.lines.first.top, 0.2);
    expect(r.lines[1].left, 0.2);
    expect(r.doubts, {0, 1}, reason: 'el lector común vio otras palabras en los dos');
  });

  test('si no coinciden los números, el renglón queda marcado', () {
    final r = alignReadLines(['placa de circulación 1234ABC'], [_at('placa de circulación 1284ABC', 0.2)]);
    expect(r.doubts, {0});
  });

  test('si coinciden, no se marca', () {
    final r = alignReadLines(['Poder Notarial N° 100/2000'], [_at('Poder Notarial Nº 100/2000', 0.2)]);
    expect(r.doubts, isEmpty);
  });

  test('si la IA cambia una palabra, el renglón queda marcado', () {
    final r = alignReadLines(
      ['que realice la denuncia ante la policía', 'OTROS. Se tenga presente'],
      [_at('que realizo la denuncia ante la policía', 0.2), _at('OTROSI. Se tenga presente', 0.24)],
    );
    expect(r.doubts, {0, 1});
  });

  test('tildes, espacios, puntuación y mayúsculas no marcan', () {
    final r = alignReadLines(
      ['razón de la Policía, en el año 2020.', 'Don Juan:  N° 15'],
      [_at('razon de la policia en el año 2020', 0.2), _at('Don  Juan Nº 15', 0.24)],
    );
    expect(r.doubts, isEmpty);
  });

  test('la ñ cuenta: «año» no es «ano»', () {
    final r = alignReadLines(['en el año pasado'], [_at('en el ano pasado', 0.2)]);
    expect(r.doubts, {0});
  });

  test('los errores típicos del lector común no marcan', () {
    final r = alignReadLines(
      [
        'de conformidad con la policía',
        'en horas de fecha y quien es',
        'por IITCUP con C.I. de las partes',
        'placa de circulación',
        'Cedula de identidad',
      ],
      [
        _at('de contormidad con la policla', 0.2),
        _at('en horas de feha y quen es', 0.24),
        _at('por I|TCUP con C.l. de 1as partes', 0.28),
        _at('placa de circulaciön', 0.32),
        _at('Cedula de ldentidad', 0.36),
      ],
    );
    expect(r.doubts, isEmpty);
  });

  test('lo que cambió la IA en hojas reales sí marca', () {
    final r = alignReadLines(
      ['del CPP formula denuncia', 'de garantía, devoluble al final', 'OTROS 2. Solicito', 'que nos dieron'],
      [
        _at('del CPP formulo denuncia', 0.2),
        _at('de garantía, devolvible al final', 0.24),
        _at('OTROSI 2. Solicito', 0.28),
        _at('que no dieron', 0.32),
      ],
    );
    expect(r.doubts, {0, 1, 2, 3});
  });

  test('un número nunca pasa por letra parecida', () {
    final r = alignReadLines(['placa 1489 de la'], [_at('placa l489 de la', 0.2)]);
    expect(r.doubts, {0});
    final extra = alignReadLines(['placa 34160 de la'], [_at('placa 3460 de la', 0.2)]);
    expect(extra.doubts, {0}, reason: 'un dígito de más no es una letra perdida');
  });

  group('lecturas reales de los dos lectores', () {
    int marked(List<(String, String)> pairs) => alignReadLines(
      [for (final p in pairs) p.$1],
      [for (final (i, p) in pairs.indexed) _at(p.$2, 0.1 + i * 0.05)],
    ).doubts.length;

    test('hoja firmada: de 10 diferencias quedan la real y las que no se pueden descartar', () {
      final r = alignReadLines(
        [
          'sufrir más agresiones, no conformes con ellos se dispusieron a sustraer las',
          'placa de circulación, retrovisores, entre otros, de esta forma mi primo fue a',
          'pedir el auxilio de la policía, cuando estos se hicieron presentes para rescatar',
          'El Prado, habiendo recuperado el mismo en horas de la mañana de fecha',
          'Por todo lo expuesto de conformidad al Art. 284 y Art. 285 del CPP formulo',
          '> Cedula de identidad',
          '> DVD de los videos y grabaciones que realice a los sindicados.',
          '> Juan Pérez Rojas con C.I. 1234567 LP.',
          'OTROSi 2°.- Solicito que por IITCUP proceda al desdoblamiento, captura y',
          '> Al Organismo Operativo de Transito a efectos de que informe quien es',
        ],
        [
          _at('sufrir más agresioneS, no contormes con ellos se dicpusieron a Sustraer las', 0.10),
          _at('placa de circulaciön, retrovisores, entre otros, de esta forma mi primo fue a', 0.15),
          _at('pedir el auxilio de la policla, cuando estos se hicieron presentes para rescatar', 0.20),
          _at('El Prado, habiendo recuperado el mismo en horas de la mañana de feha', 0.25),
          _at('Por todo lo expuesto de contormidad al Art. 284 y Art. 285 del CPP formulo', 0.30),
          _at('Cedula de ldentidad', 0.35),
          _at('> DVD de los videos y grabaciones que realizo a los sindicados.', 0.40),
          _at('Juan Pérez Rojas con C.. 1234567 LP.', 0.45),
          _at('OTROSI 2°.- Solicito que por I|TCUP proceda al desdoblamiento, captura y', 0.50),
          _at('> Al Organismo Operativo de Transito a efectos de que informe quen es', 0.55),
        ],
      );
      expect(r.doubts, {0, 6, 7}, reason: 'dicpusieron (c/s), realice (real), C.. (se perdió la I)');
    });

    test('hoja arrugada: formula sigue marcado', () {
      expect(
        marked([
          (
            'Por todo lo expuesto de conformidad al Art. 284 y Art. 285 del CPP formula',
            'Por todo lo expuesto de conformidad al Art. 284 y Art. 285 del CPP formulo',
          ),
        ]),
        1,
      );
      expect(
        marked([
          (
            'sancionado en el Art. 332 Núm. 2) del Código Penal, de mi vehículo con las',
            'sancionado en el Àrt. 332 Núm. 2) del Código Penal, de mi vehículo con las',
          ),
          (
            'modelo 2021, placa de circulación 1234ABC, solicitando a su autoridad',
            'modeío 2021, placa de circulación 1234ABC, solicitando a su autoridad',
          ),
          (
            'sufrir más agresiones, no conformes con ellos se dispusieron a sustraer las',
            'sufrir más agresiones, no Conformes con ellos se dispusieron a Sustraer 1as',
          ),
        ]),
        0,
      );
    });

    test('contrato: devoluble sigue marcado', () {
      expect(
        marked([
          (
            'SEGUNDA.- El depósito de garantía es de Bs. 2.500, devoluble al final.',
            'SEGUNDA.- El depósito de garantia es de Bs. 2.500, devolvible al final.',
          ),
        ]),
        1,
      );
    });
  });

  test('un renglón que el lector común vio en pedazos no se marca', () {
    final r = alignReadLines(
      ['Poder Notarial otorgado ante la Notaria'],
      [_at('ante la Notaria', 0.2, left: 0.5), _at('Poder Notarial otorgado', 0.201)],
    );
    expect(r.doubts, isEmpty);
    final wrong = alignReadLines(
      ['Poder Notarial otorgado ante la Notario'],
      [_at('ante la Notaria', 0.2, left: 0.5), _at('Poder Notarial otorgado', 0.201)],
    );
    expect(wrong.doubts, {0});
  });

  test('columnas que la IA lee por separado tampoco se marcan', () {
    final r = alignReadLines(['Propietaria', 'Inquilino'], [_at('Propietaria', 0.2), _at('Inquilino', 0.2, left: 0.6)]);
    expect(r.doubts, isEmpty);
  });

  test('un renglón que el lector común no vio se marca y no se pierde', () {
    final r = alignReadLines(
      ['primer renglón del texto', 'esto no estaba', 'tercer renglón del texto'],
      [_at('primer renglón del texto', 0.2), _at('tercer renglón del texto', 0.24)],
    );
    expect(r.lines, hasLength(3));
    expect(r.doubts, {1});
    expect(r.lines[1].top, greaterThan(0.2));
    expect(r.lines[2].top, 0.24);
  });

  test('sin lector común igual da renglones, todos para revisar', () {
    final r = alignReadLines(['uno', 'dos'], const []);
    expect(r.lines, hasLength(2));
    expect(r.doubts, {0, 1});
  });

  test('limpia la respuesta de la IA', () {
    expect(linesFromAiText('```\nuno\n\n  dos \n```'), ['uno', 'dos']);
  });

  test('sin par: el lugar es estimado', () {
    final out = alignReadLines(
      ['nada que ver con esto'],
      [(text: 'otra cosa', left: 0.1, top: 0.1, width: 0.5, height: 0.02)],
    );
    expect(out.guessed, {0});
    expect(out.doubts, {0});
  });

  test('si la IA dice que no ve texto, no hay renglones', () {
    expect(linesFromAiText('No hay texto en español en la imagen.'), isEmpty);
    expect(linesFromAiText('NONE'), isEmpty);
    expect(linesFromAiText('The image contains no text.'), isEmpty);
    expect(linesFromAiText('No hay texto\nsegundo renglón'), hasLength(2), reason: 'dos renglones sí son de la hoja');
    expect(linesFromAiText('No hay derecho a reclamar'), hasLength(1));
  });
}
