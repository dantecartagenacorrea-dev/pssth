import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/spanish_numbers.dart';

void main() {
  test('unidades, decenas y los casos especiales', () {
    expect(spanishNumber('0'), 'cero');
    expect(spanishNumber('5'), 'cinco');
    expect(spanishNumber('15'), 'quince');
    expect(spanishNumber('16'), 'dieciséis');
    expect(spanishNumber('21'), 'veintiuno');
    expect(spanishNumber('22'), 'veintidós');
    expect(spanishNumber('30'), 'treinta');
    expect(spanishNumber('45'), 'cuarenta y cinco');
  });

  test('centenas', () {
    expect(spanishNumber('100'), 'cien');
    expect(spanishNumber('101'), 'ciento uno');
    expect(spanishNumber('250'), 'doscientos cincuenta');
    expect(spanishNumber('500'), 'quinientos');
    expect(spanishNumber('999'), 'novecientos noventa y nueve');
  });

  test('miles y millones', () {
    expect(spanishNumber('1000'), 'mil');
    expect(spanishNumber('2024'), 'dos mil veinticuatro');
    expect(spanishNumber('21000'), 'veintiún mil');
    expect(spanishNumber('100000'), 'cien mil');
    expect(spanishNumber('1000000'), 'un millón');
    expect(spanishNumber('2500000'), 'dos millones quinientos mil');
  });

  test('formato boliviano: punto de miles y coma decimal', () {
    expect(spanishNumber('1.234'), 'mil doscientos treinta y cuatro');
    expect(spanishNumber('1.234,50'), 'mil doscientos treinta y cuatro coma cincuenta');
    expect(spanishNumber('3,5'), 'tres coma cinco');
    expect(spanishNumber('0,05'), 'cero coma cero cinco');
  });

  test('punto decimal cuando no son grupos de miles', () {
    expect(spanishNumber('3.5'), 'tres punto cinco');
  });

  test('reemplaza los números dentro de un texto', () {
    expect(numbersToWords('Artículo 5 del año 2024, pagó 1.234,50 bolivianos.'),
        'Artículo cinco del año dos mil veinticuatro, pagó mil doscientos treinta y cuatro coma cincuenta bolivianos.');
  });
}
