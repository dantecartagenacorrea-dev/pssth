import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/export_names.dart';

void main() {
  test('usa el nombre visible y conserva la extensión del archivo guardado', () {
    expect(exportNames([(name: 'Clase de hoy', storedPath: '/lib/123.pdf')]), ['Clase de hoy.pdf']);
    expect(exportNames([(name: 'Informe.pdf', storedPath: '/lib/123.pdf')]), ['Informe.pdf']);
  });

  test('no duplica una extensión que solo cambia en mayúsculas', () {
    expect(exportNames([(name: 'Foto.JPG', storedPath: '/lib/9.jpg')]), ['Foto.JPG']);
  });

  test('un punto dentro del nombre no cuenta como extensión', () {
    expect(exportNames([(name: 'Grabación 04.11', storedPath: '/lib/1.txt')]), ['Grabación 04.11.txt']);
  });

  test('quita los caracteres que los sistemas de archivos no aceptan', () {
    expect(exportNames([(name: 'a/b:c*d?.pdf', storedPath: '/lib/1.pdf')]), ['a_b_c_d_.pdf']);
  });

  test('nunca sale de la carpeta temporal', () {
    expect(exportNames([(name: '../../secreto', storedPath: '/lib/1.txt')]), ['.._.._secreto.txt']);
  });

  test('un nombre vacío recibe uno genérico', () {
    expect(exportNames([(name: '   ', storedPath: '/lib/1.pdf')]), ['Documento.pdf']);
  });

  test('numera los nombres repetidos sin importar mayúsculas', () {
    expect(
      exportNames([
        (name: 'Acta.pdf', storedPath: '/lib/1.pdf'),
        (name: 'acta.pdf', storedPath: '/lib/2.pdf'),
        (name: 'Acta.pdf', storedPath: '/lib/3.pdf'),
      ]),
      ['Acta.pdf', 'acta (2).pdf', 'Acta (3).pdf'],
    );
  });
}
