import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/retype_ink.dart';
import 'package:lector_pdf/domain/retyped_pdf.dart';
import 'package:lector_pdf/domain/scanned_pdf.dart';

/// JPEG mínimo válido de 1×1 píxel.
final _jpeg = base64Decode(
  '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=',
);

/// Cada letra mide medio tamaño de letra.
double _measure(String text, bool bold) => text.length * 0.5;

ScannedLine _line(String text, double left, double top, {double width = 0.8, double height = 0.02}) =>
    (text: text, left: left, top: top, width: width, height: height);

void main() {
  List<List<FlowLine>> lay(List<ScannedLine> lines) => layoutParagraphs(paragraphsFrom(lines), measure: _measure);
  List<String> texts(Paragraph p) => [for (final w in p.words) w.text];

  group('párrafos', () {
    test('los cortes de renglón de la hoja vieja desaparecen', () {
      final ps = paragraphsFrom([
        _line('uno dos', 0.1, 0.20),
        _line('tres cuatro', 0.1, 0.22),
        _line('fin', 0.1, 0.24, width: 0.1),
      ]);
      expect(ps, hasLength(1));
      expect(texts(ps.single), ['uno', 'dos', 'tres', 'cuatro', 'fin']);
    });

    test('un renglón corto termina el párrafo', () {
      final ps = paragraphsFrom([
        _line('fin de uno', 0.1, 0.20, width: 0.3),
        _line('otro párrafo largo', 0.1, 0.22),
        _line('sigue', 0.1, 0.24),
      ]);
      expect(ps, hasLength(2));
      expect(texts(ps[1]), ['otro', 'párrafo', 'largo', 'sigue']);
    });

    test('la separación grande y las viñetas empiezan párrafo', () {
      final ps = paragraphsFrom([
        _line('primero', 0.1, 0.20),
        _line('segundo', 0.1, 0.22),
        _line('tercero', 0.1, 0.24),
        _line('aparte', 0.1, 0.32),
        _line('> viñeta', 0.2, 0.34),
        _line('> otra', 0.2, 0.36),
      ]);
      expect(ps, hasLength(4));
      expect(ps[1].spaced, isTrue);
      expect(ps[2].firstIndent, greaterThan(0));
      expect(texts(ps[3]).first, '»');
    });

    test('una viñeta conserva la sangría en su segundo renglón', () {
      final ps = paragraphsFrom([
        _line('texto largo normal', 0.1, 0.20),
        _line('> viñeta muy larga', 0.15, 0.22),
        _line('que sigue aquí', 0.2, 0.24),
      ]);
      expect(ps.last.restIndent, greaterThan(ps.last.firstIndent));
    });

    test('junta los pedazos de un renglón y limpia espacios', () {
      final ps = paragraphsFrom([
        _line('En calidad', 0.3, 0.2, width: 0.2),
        _line('OTROSI.-', 0.1, 0.201, width: 0.15),
      ]);
      expect(texts(ps.single), ['OTROSI.-', 'En', 'calidad']);
    });

    test('las viñetas quedan alineadas aunque el lector no haya visto alguna', () {
      final ps = paragraphsFrom([
        _line('texto largo del documento', 0.1, 0.1),
        _line('> primera', 0.2, 0.2, width: 0.3),
        _line('> segunda sin viñeta leída', 0.25, 0.25, width: 0.3),
      ]);
      expect(ps[1].firstIndent, ps[2].firstIndent);
    });

    test('una caja alta de hoja torcida no parte el párrafo', () {
      final ps = paragraphsFrom([
        _line('uno', 0.1, 0.10),
        _line('dos', 0.1, 0.12),
        _line('tres', 0.1, 0.135, height: 0.03),
        _line('cuatro', 0.1, 0.16),
        _line('cinco', 0.1, 0.18),
      ]);
      expect(ps, hasLength(1));
    });

    test('dos renglones de una hoja torcida no se juntan ni se desordenan', () {
      final ps = paragraphsFrom([
        (text: 'el', left: 0.067, top: 0.247, width: 0.769, height: 0.035),
        (text: 'sindicado', left: 0.077, top: 0.265, width: 0.760, height: 0.048),
        (text: 'Los', left: 0.071, top: 0.292, width: 0.767, height: 0.030),
        (text: 'catorce', left: 0.075, top: 0.316, width: 0.208, height: 0.013),
      ]);
      expect(ps.expand(texts), ['el', 'sindicado', 'Los', 'catorce']);
      expect(ps, hasLength(1));
    });

    test('en una hoja con muchos saltos se siguen viendo como saltos', () {
      final ps = paragraphsFrom([
        _line('uno', 0.1, 0.10),
        _line('dos', 0.1, 0.13),
        _line('tres', 0.1, 0.19),
        _line('cuatro', 0.1, 0.25),
        _line('cinco', 0.1, 0.31),
        _line('seis', 0.1, 0.34),
      ]);
      expect(ps.where((p) => p.spaced), hasLength(3));
    });

    test('un título en mayúsculas va solo y en negrita', () {
      final ps = paragraphsFrom([
        _line('PETITORIO.', 0.1, 0.20, width: 0.15),
        _line('Por todo lo expuesto', 0.1, 0.22),
      ]);
      expect(ps, hasLength(2));
      expect(ps[0].words.single.bold, isTrue);
      expect(ps[1].words.first.bold, isFalse);
    });
  });

  group('negritas', () {
    bool boldOf(List<Paragraph> ps, String word) => ps.single.words.firstWhere((w) => w.text == word).bold;

    test('van las que se midieron en la foto, no las mayúsculas', () {
      final ps = paragraphsFrom(
        [_line('por IITCUP contra DENUNCIA fin', 0.1, 0.2)],
        bold: [
          [false, false, false, true, false],
        ],
      );
      expect(boldOf(ps, 'IITCUP'), isFalse);
      expect(boldOf(ps, 'DENUNCIA'), isTrue);
    });

    test('sin medida, las mayúsculas sueltas no van en negrita', () {
      final ps = paragraphsFrom([_line('el DVD y ROBO AGRAVADO fin', 0.1, 0.2)]);
      expect(boldOf(ps, 'ROBO'), isFalse);
    });

    test('un título medido como normal queda normal', () {
      final ps = paragraphsFrom(
        [_line('LOS AUTORES', 0.1, 0.2, width: 0.15)],
        bold: [
          [false, false],
        ],
      );
      expect(ps.single.words.first.bold, isFalse);
    });

    test('la viñeta pegada no corre las negritas', () {
      final ps = paragraphsFrom(
        [_line('>Palabra FUERTE', 0.1, 0.2)],
        bold: [
          [false, true],
        ],
      );
      expect(boldOf(ps, 'FUERTE'), isTrue);
    });
  });

  group('hoja nueva', () {
    test('márgenes parejos: todo renglón justificado llega al borde', () {
      final long = List.filled(60, 'palabra').join(' ');
      final pages = lay([_line(long, 0.1, 0.2)]);
      final line = pages.single.first;
      expect(line.words.first.x, 72);
      final last = line.words.last;
      expect(last.x + _measure(last.text, false) * 12, closeTo(540, 0.01));
    });

    test('el último renglón del párrafo no se estira', () {
      final pages = lay([_line('corto final', 0.1, 0.2)]);
      final line = pages.single.single;
      expect(line.words.last.x, lessThan(200));
    });

    test('lo que no entra sigue en otra hoja y no se pierde nada', () {
      final long = List.filled(3000, 'palabra').join(' ');
      final pages = lay([_line(long, 0.1, 0.2)]);
      expect(pages.length, greaterThan(1));
      expect(pages.expand((p) => p).expand((l) => l.words).length, 3000);
      for (final p in pages) {
        expect(p.last.y + 16.2, lessThanOrEqualTo(792 - 72));
      }
    });

    test('una firma va entre sus párrafos y corre lo que sigue', () {
      final lines = [_line('primero', 0.1, 0.2, width: 0.4), _line('segundo', 0.1, 0.6)];
      final paragraphs = paragraphsFrom(lines);
      final mark = (jpeg: Uint8List.fromList(_jpeg), left: 0.5, top: 0.4, boxWidth: 0.2, boxHeight: 0.1);
      final rows = markRowsFrom([mark], paragraphs, lines, 1000, pageHeight: 1000);
      expect(rows.single.before, 1);
      expect(rows.single.marks.single.width, closeTo(0.2 / 0.8 * 468, 0.01));
      final page = layoutParagraphs(paragraphs, measure: _measure, marks: rows).single;
      expect(page.map((l) => l.words.isEmpty), [false, true, false]);
      expect(page[2].y, greaterThanOrEqualTo(page[1].y + rows.single.height));
      expect(page[1].marks.single.x, closeTo(72 + 0.4 / 0.8 * 468, 0.01));
    });

    test('dos firmas a la misma altura van lado a lado', () {
      final lines = [_line('texto', 0.1, 0.2)];
      PageMark at(double left) =>
          (jpeg: Uint8List.fromList(_jpeg), left: left, top: 0.5, boxWidth: 0.2, boxHeight: 0.1);
      final rows = markRowsFrom([at(0.1), at(0.6)], paragraphsFrom(lines), lines, 1000, pageHeight: 1000);
      expect(rows.single.marks, hasLength(2));
      expect(rows.single.before, 1, reason: 'después del último párrafo');
    });

    test('lo que no entra en la hoja pasa entero a la siguiente', () {
      final long = List.filled(600, 'palabra').join(' ');
      final lines = [_line(long, 0.1, 0.1)];
      final paragraphs = paragraphsFrom(lines);
      final mark = (jpeg: Uint8List.fromList(_jpeg), left: 0.1, top: 0.9, boxWidth: 0.8, boxHeight: 0.4);
      final rows = markRowsFrom([mark], paragraphs, lines, 1000, pageHeight: 1000);
      final pages = layoutParagraphs(paragraphs, measure: _measure, marks: rows);
      final where = pages.expand((p) => p).firstWhere((l) => l.marks.isNotEmpty);
      expect(where.y + rows.single.height, lessThanOrEqualTo(792 - 72));
    });

    test('sin texto no hay hojas', () {
      expect(lay(const []), isEmpty);
    });
  });

  test('la firma aparece como imagen en el PDF', () async {
    final jpeg = Uint8List.fromList(_jpeg);
    final raw = latin1.decode(
      await buildRetypedPdf(
        [
          (jpeg: jpeg, width: 1000, height: 1400, lines: [_line('texto', 0.1, 0.2)]),
        ],
        compress: false,
        ink: [
          (
            bold: const [null],
            marks: [(jpeg: jpeg, left: 0.1, top: 0.5, boxWidth: 0.2, boxHeight: 0.1)],
            stamps: const <int>{},
          ),
        ],
      ),
    );
    expect(raw, contains('texto'));
    expect(raw, matches(RegExp(r'/Subtype\s*/Image')));
  });

  test('el PDF lleva el texto visible, sin foto, y la foto si no se leyó nada', () async {
    final jpeg = Uint8List.fromList(_jpeg);
    final bytes = await buildRetypedPdf([
      (jpeg: jpeg, width: 1000, height: 1400, lines: [_line('Núm. 123 — placa', 0.1, 0.2)]),
    ], compress: false);
    final raw = latin1.decode(bytes);
    expect(raw, startsWith('%PDF'));
    expect(raw, contains('Núm.'));
    expect(raw, contains('placa'));
    expect(raw, isNot(matches(RegExp(r'/Subtype\s*/Image'))));
    expect(raw, isNot(contains('3 Tr')), reason: 'el texto se ve');

    final blank = latin1.decode(
      await buildRetypedPdf([(jpeg: jpeg, width: 1000, height: 1400, lines: const [])], compress: false),
    );
    expect(blank, matches(RegExp(r'/Subtype\s*/Image')));
  });
}
