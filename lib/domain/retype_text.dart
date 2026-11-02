/// ¿Parece mal leído? Una cifra pegada a minúsculas («n0») o una mayúscula después
/// de minúsculas («estoS», «mnotoriZado»). Las placas y siglas no cuentan.
bool looksMisread(String text) {
  final letterDigit = RegExp(r'[a-záéíóúñ]\d|\d[a-záéíóúñ]');
  final innerCapital = RegExp(r'[a-záéíóúñ][A-ZÁÉÍÓÚÑ]');
  return text.split(RegExp(r'\s+')).any((word) {
    if (word.contains('(') || word.contains('=')) return false; // sen(30), 2x=4
    return letterDigit.hasMatch(word) || innerCapital.hasMatch(word);
  });
}
