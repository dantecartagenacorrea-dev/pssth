// Números escritos con cifras -> palabras en español, para la voz natural
// (antes lo hacía espeak-ng). Formato boliviano: punto de miles, coma decimal.

const _unidades = [
  'cero', 'uno', 'dos', 'tres', 'cuatro', 'cinco', 'seis', 'siete', 'ocho', 'nueve',
  'diez', 'once', 'doce', 'trece', 'catorce', 'quince', 'dieciséis', 'diecisiete', 'dieciocho', 'diecinueve',
  'veinte', 'veintiuno', 'veintidós', 'veintitrés', 'veinticuatro', 'veinticinco', 'veintiséis', 'veintisiete',
  'veintiocho', 'veintinueve',
];
const _decenas = ['', '', '', 'treinta', 'cuarenta', 'cincuenta', 'sesenta', 'setenta', 'ochenta', 'noventa'];
const _centenas = [
  '', 'ciento', 'doscientos', 'trescientos', 'cuatrocientos', 'quinientos', 'seiscientos', 'setecientos',
  'ochocientos', 'novecientos',
];

String _menorDeMil(int n) {
  if (n < 30) return _unidades[n];
  if (n < 100) {
    final d = _decenas[n ~/ 10];
    return n % 10 == 0 ? d : '$d y ${_unidades[n % 10]}';
  }
  if (n == 100) return 'cien';
  final resto = n % 100;
  return resto == 0 ? _centenas[n ~/ 100] : '${_centenas[n ~/ 100]} ${_menorDeMil(resto)}';
}

/// "uno" delante de "mil" o "millones" se apocopa: veintiún mil, un millón.
String _apocope(String s) => s.endsWith('veintiuno')
    ? '${s.substring(0, s.length - 9)}veintiún'
    : s.endsWith('uno')
        ? '${s.substring(0, s.length - 3)}un'
        : s;

String _entero(int n) {
  if (n < 1000) return _menorDeMil(n);
  if (n < 1000000) {
    final miles = n ~/ 1000;
    final resto = n % 1000;
    final m = miles == 1 ? 'mil' : '${_apocope(_menorDeMil(miles))} mil';
    return resto == 0 ? m : '$m ${_menorDeMil(resto)}';
  }
  final millones = n ~/ 1000000;
  final resto = n % 1000000;
  final m = millones == 1 ? 'un millón' : '${_apocope(_entero(millones))} millones';
  return resto == 0 ? m : '$m ${_entero(resto)}';
}

String _cifras(String digits) => digits.split('').map((d) => _unidades[int.parse(d)]).join(' ');

/// Un número tal como aparece en el texto ("1.234,50", "2024", "3,5").
String spanishNumber(String raw) {
  var entero = raw;
  String? decimales;
  var separador = 'coma';
  if (raw.contains(',')) {
    final p = raw.split(',');
    entero = p.first;
    decimales = p.last;
  }
  if (RegExp(r'^\d{1,3}(\.\d{3})+$').hasMatch(entero)) {
    entero = entero.replaceAll('.', '');
  } else if (entero.contains('.') && decimales == null) {
    final p = entero.split('.');
    entero = p.first;
    decimales = p.last;
    separador = 'punto';
  }
  final n = int.tryParse(entero);
  if (n == null || n >= 1000000000000) return _cifras(raw.replaceAll(RegExp(r'\D'), ''));
  final palabras = _entero(n);
  if (decimales == null || decimales.isEmpty) return palabras;
  final dec = decimales.startsWith('0') ? _cifras(decimales) : _entero(int.parse(decimales));
  return '$palabras $separador $dec';
}

final _numero = RegExp(r'\d+(?:[.,]\d+)*');

/// Sustituye cada número del texto por sus palabras.
String numbersToWords(String text) => text.replaceAllMapped(_numero, (m) => spanishNumber(m[0]!));
