/// Reordena fragmentos de texto de una página cuando hay dos columnas claras.
///
/// Conservador por diseño: si no se detecta un canal vertical vacío que separe
/// dos bloques de texto sustanciales, devuelve `null` y se usa el texto
/// original tal cual lo entrega el PDF.
class TextBox {
  const TextBox({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final String text;
  final double left;
  /// Coordenada mayor = más arriba (sistema PDF, origen abajo-izquierda).
  final double top;
  final double right;
  final double bottom;

  double get cx => (left + right) / 2;
  double get cy => (top + bottom) / 2;
  double get height => (top - bottom).abs();
}

String? reorderColumns(List<TextBox> boxes, double pageWidth) {
  final items = boxes.where((b) => b.text.trim().isNotEmpty && b.right > b.left).toList();
  if (items.length < 8 || pageWidth <= 0) return null;

  // Histograma de cobertura horizontal.
  const bins = 200;
  final cover = List<int>.filled(bins, 0);
  for (final b in items) {
    // Los bloques muy anchos (títulos a toda página) no definen columnas.
    if ((b.right - b.left) > pageWidth * 0.6) continue;
    final a = ((b.left / pageWidth) * bins).floor().clamp(0, bins - 1);
    final z = ((b.right / pageWidth) * bins).ceil().clamp(0, bins - 1);
    for (var i = a; i <= z; i++) {
      cover[i]++;
    }
  }

  // Buscar el canal (casi) vacío más ancho entre el 30 % y el 70 % del ancho.
  // Se tolera que algún título centrado lo cruce: umbral del 12 % del máximo.
  final maxCover = cover.fold(0, (m, v) => v > m ? v : m);
  final umbral = (maxCover * 0.12).floor();
  int bestStart = -1, bestLen = 0;
  var i = (bins * 0.30).floor();
  final end = (bins * 0.70).ceil();
  while (i < end) {
    if (cover[i] <= umbral) {
      var j = i;
      while (j < end && cover[j] <= umbral) {
        j++;
      }
      if (j - i > bestLen) {
        bestLen = j - i;
        bestStart = i;
      }
      i = j;
    } else {
      i++;
    }
  }
  if (bestStart < 0 || bestLen < bins * 0.015) return null;
  final gutter = ((bestStart + bestLen / 2) / bins) * pageWidth;

  final left = <TextBox>[];
  final right = <TextBox>[];
  final full = <TextBox>[];
  for (final b in items) {
    if (b.right <= gutter) {
      left.add(b);
    } else if (b.left >= gutter) {
      right.add(b);
    } else {
      full.add(b); // títulos u otros bloques que cruzan el canal
    }
  }
  int chars(List<TextBox> l) => l.fold(0, (n, b) => n + b.text.trim().length);
  final total = chars(items);
  if (total == 0) return null;
  // Ambas columnas deben tener texto sustancial.
  if (chars(left) < total * 0.2 || chars(right) < total * 0.2) return null;

  // Bandas: los bloques a ancho completo separan la página en franjas y
  // dentro de cada franja se lee la columna izquierda y luego la derecha.
  full.sort((a, b) => b.top.compareTo(a.top));
  final cuts = [double.infinity, ...full.map((f) => f.cy), double.negativeInfinity];
  final out = StringBuffer();
  for (var k = 0; k < cuts.length - 1; k++) {
    final hi = cuts[k], lo = cuts[k + 1];
    if (k > 0) {
      final f = full[k - 1];
      _appendLines(out, [f]);
    }
    bool inBand(TextBox b) => b.cy < hi && b.cy >= lo;
    _appendLines(out, left.where(inBand).toList());
    _appendLines(out, right.where(inBand).toList());
  }
  return out.toString().trim();
}

void _appendLines(StringBuffer out, List<TextBox> boxes) {
  if (boxes.isEmpty) return;
  boxes.sort((a, b) {
    final dy = b.cy.compareTo(a.cy);
    return dy != 0 ? dy : a.left.compareTo(b.left);
  });
  final lines = <List<TextBox>>[];
  for (final b in boxes) {
    if (lines.isNotEmpty) {
      final last = lines.last.first;
      final tol = (last.height + b.height) / 4;
      if ((last.cy - b.cy).abs() <= tol) {
        lines.last.add(b);
        continue;
      }
    }
    lines.add([b]);
  }
  for (final line in lines) {
    line.sort((a, b) => a.left.compareTo(b.left));
    out.writeln(line.map((b) => b.text.trim()).where((t) => t.isNotEmpty).join(' '));
  }
}

/// Rectángulo simple de un carácter (coordenadas PDF: top > bottom).
class CharRect {
  const CharRect(this.left, this.top, this.right, this.bottom);
  final double left, top, right, bottom;
}

/// Construye bloques de texto a partir de los caracteres de la página,
/// cortando cuando cambia la línea o hay un hueco horizontal grande
/// (así dos columnas en la misma línea quedan en bloques distintos).
List<TextBox> boxesFromChars(String text, List<CharRect> rects) {
  final n = text.length < rects.length ? text.length : rects.length;
  final out = <TextBox>[];
  var buf = StringBuffer();
  double l = 0, t = 0, r = 0, b = 0;
  double sumW = 0;
  var cnt = 0;
  CharRect? prev;

  void flush() {
    final s = buf.toString().trim();
    if (s.isNotEmpty) out.add(TextBox(text: s, left: l, top: t, right: r, bottom: b));
    buf = StringBuffer();
    prev = null;
    sumW = 0;
    cnt = 0;
  }

  for (var i = 0; i < n; i++) {
    final ch = text[i];
    final c = rects[i];
    if (ch == '\n' || ch == '\r') {
      flush();
      continue;
    }
    final w = (c.right - c.left).abs();
    final h = (c.top - c.bottom).abs();
    if (ch.trim().isEmpty) {
      // Espacio: solo separa si el siguiente carácter está lejos; lo decide él.
      if (prev != null) buf.write(' ');
      continue;
    }
    if (prev != null) {
      final avgW = cnt > 0 ? sumW / cnt : w;
      final sameLine = ((prev!.top + prev!.bottom) / 2 - (c.top + c.bottom) / 2).abs() <= h * 0.5;
      final gap = c.left - prev!.right;
      if (!sameLine || gap > avgW * 2.5 || gap < -avgW * 3) {
        flush();
      }
    }
    if (prev == null) {
      l = c.left;
      t = c.top;
      r = c.right;
      b = c.bottom;
    } else {
      if (c.left < l) l = c.left;
      if (c.top > t) t = c.top;
      if (c.right > r) r = c.right;
      if (c.bottom < b) b = c.bottom;
    }
    buf.write(ch);
    prev = c;
    if (w > 0) {
      sumW += w;
      cnt++;
    }
  }
  flush();
  return out;
}
