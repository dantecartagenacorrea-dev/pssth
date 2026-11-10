/// Letras que el lector confunde con números: dentro de un número son el número.
const _lookalikes = {'o': '0', 'O': '0', 'l': '1', 'I': '1', 's': '5', 'S': '5'};

/// Un número con letras parecidas metidas: empieza con un dígito y no tiene otra
/// cosa que dígitos, esas letras y separadores (7oooO00, 1s/o3/2024).
final _numberLike = RegExp(r'(?<![\w@])\d[0-9oOlIsS/.\-]{3,}(?![\w@])');

/// Cambia por dígitos las letras parecidas que el lector puso dentro de números
/// (teléfonos, fechas, montos). Una palabra no se toca: tiene que empezar con un
/// dígito y no tener ninguna otra letra.
String fixDigitLookalikes(String text) => text.replaceAllMapped(_numberLike, (m) {
  final token = m[0]!;
  if (!token.contains(RegExp('[oOlIsS]'))) return token;
  return token.split('').map((c) => _lookalikes[c] ?? c).join();
});
