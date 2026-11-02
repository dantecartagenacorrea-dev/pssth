import 'dart:math' as math;
import 'dart:typed_data';

/// Un rectángulo de la imagen, en píxeles (right y bottom no se incluyen).
typedef InkBox = ({int left, int top, int right, int bottom});

/// Una raya de fracción con lo que tiene arriba y abajo.
typedef FractionBar = ({InkBox numerator, InkBox denominator, int left, int right, int y});

/// Busca las rayas de fracción en una imagen en blanco y negro ([dark]: un byte
/// por píxel, distinto de 0 si hay tinta). Una raya es un trazo horizontal fino
/// con un número encima y otro debajo, que a mano suelen rozarla: así no se
/// confunde con un signo menos, un «=», un «÷» ni el trazo de un 5 o un 7.
/// De izquierda a derecha.
List<FractionBar> findFractionBars(Uint8List dark, int w, int h) {
  final found = <FractionBar>[];
  for (final run in _strokes(dark, w, h)) {
    final length = run.right - run.left;
    if (run.bottom - run.top > math.max(3, length * 0.3)) continue;
    final above = _inkBeside(dark, w, h, run, up: true);
    final below = _inkBeside(dark, w, h, run, up: false);
    if (above == null || below == null) continue;
    bool sticksOut(InkBox b) => b.left - run.left >= length * 0.05 && run.right - b.right >= length * 0.05;
    // Si roza algo, tiene que sobresalir a los dos lados de lo que roza, como una
    // raya; así no cuenta la barrita de un 4, ni el trazo de un 5, ni un «+».
    if (above.touches && !sticksOut(above.box)) continue;
    if (below.touches && !sticksOut(below.box)) continue;
    if (above.touches && below.touches && (above.box.right - above.box.left) < length * 0.3) continue;
    found.add((numerator: above.box, denominator: below.box, left: run.left, right: run.right, y: run.top));
  }
  return found..sort((a, b) => a.left.compareTo(b.left));
}

/// Los trazos horizontales: tramos de tinta largos que siguen de fila en fila,
/// aunque la foto esté torcida.
List<InkBox> _strokes(Uint8List dark, int w, int h) {
  final minLength = math.max(10, w ~/ 80);
  final done = <InkBox>[];
  var open = <List<InkBox>>[];
  for (var y = 0; y < h; y++) {
    final next = <List<InkBox>>[];
    var x = 0;
    while (x < w) {
      if (dark[y * w + x] == 0) {
        x++;
        continue;
      }
      final start = x;
      while (x < w && dark[y * w + x] != 0) {
        x++;
      }
      if (x - start < minLength) continue;
      final row = (left: start, top: y, right: x, bottom: y + 1);
      // Sigue un trazo de la fila de arriba, si coincide en buena parte.
      List<InkBox>? parent;
      for (final o in open) {
        final last = o.last;
        final overlap = math.min(last.right, x) - math.max(last.left, start);
        if (overlap >= math.min(x - start, last.right - last.left) ~/ 2) {
          parent = o;
          break;
        }
      }
      if (parent != null) open.remove(parent);
      next.add([...?parent, row]);
    }
    done.addAll(open.map(_core));
    open = next;
  }
  return done..addAll(open.map(_core));
}

/// De las filas de un trazo, las del tramo largo: una cifra que roza la raya se
/// suma a sus filas, pero es mucho más angosta.
InkBox _core(List<InkBox> rows) {
  final longest = rows.map((r) => r.right - r.left).reduce(math.max);
  var bestStart = 0, bestEnd = 0, start = -1;
  for (var i = 0; i <= rows.length; i++) {
    final wide = i < rows.length && (rows[i].right - rows[i].left) * 2 >= longest;
    if (wide && start < 0) start = i;
    if (!wide && start >= 0) {
      if (i - start > bestEnd - bestStart) {
        bestStart = start;
        bestEnd = i;
      }
      start = -1;
    }
  }
  final core = rows.sublist(bestStart, bestEnd);
  return (
    left: core.map((r) => r.left).reduce(math.min),
    top: core.first.top,
    right: core.map((r) => r.right).reduce(math.max),
    bottom: core.last.bottom,
  );
}

/// Lo que hay justo encima o debajo de un trazo; null si no parece un número
/// de fracción (nada, un punto del «÷» o un renglón más ancho).
({InkBox box, bool touches})? _inkBeside(Uint8List dark, int w, int h, InkBox run, {required bool up}) {
  final length = run.right - run.left;
  final margin = (length * 0.25).ceil();
  final left = math.max(0, run.left - margin), right = math.min(w, run.right + margin);
  final step = up ? -1 : 1;
  bool rowHasInk(int y) {
    for (var x = left; x < right; x++) {
      if (dark[y * w + x] != 0) return true;
    }
    return false;
  }

  var y = up ? run.top - 1 : run.bottom;
  if (y < 0 || y >= h) return null;
  // Lo que sigue pegado de una raya torcida, unas filas, no es el número.
  var skipped = 0;
  final slope = math.max(3, length ~/ 12);
  while (y >= 0 && y < h && skipped < slope && rowHasInk(y) && !_bandIsTall(dark, w, h, left, right, y, step, slope)) {
    y += step;
    skipped++;
  }
  if (y < 0 || y >= h) return null;
  final touches = rowHasInk(y);
  final maxGap = math.max(length, 12);
  var gap = 0;
  while (y >= 0 && y < h && !rowHasInk(y)) {
    if (++gap > maxGap) return null;
    y += step;
  }
  if (y < 0 || y >= h) return null;

  final limit = math.max(length * 3, 40);
  var top = y, bottom = y;
  var boxLeft = right, boxRight = left;
  var rows = 0;
  while (y >= 0 && y < h && rows < limit && rowHasInk(y)) {
    for (var x = left; x < right; x++) {
      if (dark[y * w + x] != 0) {
        boxLeft = math.min(boxLeft, x);
        boxRight = math.max(boxRight, x + 1);
      }
    }
    top = math.min(top, y);
    bottom = math.max(bottom, y);
    y += step;
    rows++;
  }
  final inkHeight = bottom - top + 1;
  if (inkHeight < math.max(5, length * 0.25)) return null; // el punto de un «÷»
  // Si la tinta sigue más allá del margen, es un renglón de texto.
  if (boxLeft == left && left > 0 || boxRight == right && right < w) return null;
  return (box: (left: boxLeft, top: top, right: boxRight, bottom: bottom + 1), touches: touches);
}

/// ¿La tinta de esta fila sigue por más de [limit] filas? Entonces ya es otra cosa.
bool _bandIsTall(Uint8List dark, int w, int h, int left, int right, int y, int step, int limit) {
  var rows = 0;
  while (y >= 0 && y < h && rows <= limit) {
    var ink = false;
    for (var x = left; x < right && !ink; x++) {
      ink = dark[y * w + x] != 0;
    }
    if (!ink) return false;
    y += step;
    rows++;
  }
  return true;
}

/// El signo que hay en un pedazo de la imagen, por su forma: el lector de texto
/// suele saltarse los signos sueltos. null si no hay ninguno claro.
String? classifyOperator(Uint8List dark, int w, InkBox area) {
  var left = area.right, right = area.left, top = area.bottom, bottom = area.top;
  for (var y = area.top; y < area.bottom; y++) {
    for (var x = area.left; x < area.right; x++) {
      if (dark[y * w + x] != 0) {
        left = math.min(left, x);
        right = math.max(right, x + 1);
        top = math.min(top, y);
        bottom = math.max(bottom, y + 1);
      }
    }
  }
  final width = right - left, height = bottom - top;
  if (width < 4 || height < 1) return null;

  bool inkIn(int x0, int y0, int x1, int y1) {
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        if (dark[y * w + x] != 0) return true;
      }
    }
    return false;
  }

  // Bandas de tinta de arriba abajo, separadas por filas vacías.
  final bands = <({int top, int bottom})>[];
  int? start;
  for (var y = top; y <= bottom; y++) {
    final ink = y < bottom && inkIn(left, y, right, y + 1);
    if (ink) start ??= y;
    if (!ink && start != null) {
      bands.add((top: start, bottom: y));
      start = null;
    }
  }
  bool flat(({int top, int bottom}) b) => b.bottom - b.top <= width * 0.4;

  if (bands.length == 3) return flat(bands[1]) ? '÷' : null;
  if (bands.length == 2) return flat(bands[0]) && flat(bands[1]) ? '=' : null;
  if (bands.length != 1) return null;
  if (height <= width * 0.4) return '-';
  if (height > width * 2) return null;

  // Un «+» tiene tinta arriba y al costado en el centro; un «×», no: la tiene
  // en las esquinas.
  final cx = left + width ~/ 2, cy = top + height ~/ 2;
  final dx = math.max(1, width ~/ 8), dy = math.max(1, height ~/ 8);
  final topMiddle = inkIn(cx - dx, top, cx + dx + 1, top + dy);
  final leftMiddle = inkIn(left, cy - dy, left + dx, cy + dy + 1);
  final center = inkIn(cx - dx, cy - dy, cx + dx + 1, cy + dy + 1);
  final corner = inkIn(left, top, left + dx * 2, top + dy * 2);
  if (topMiddle && leftMiddle && center && !corner) return '+';
  if (corner && center && !topMiddle && !leftMiddle) return '×';
  return null;
}

/// De lo que el lector vio en un número repetido tres veces, el número. Los
/// espacios no cuentan, porque agrupa como quiere («3 33», «121212»). Corrige
/// las confusiones comunes con letras; null si las tres copias no coinciden:
/// mejor no leer que leer mal una cifra.
String? digitsFromRepeat(String ocr) {
  const swaps = {'O': '0', 'o': '0', 'l': '1', 'I': '1', '|': '1', 'S': '5', 's': '5', 'Z': '2', 'z': '2'};
  final digits = ocr.replaceAll(RegExp(r'\s+'), '').split('').map((c) => swaps[c] ?? c).join();
  if (digits.isEmpty || digits.length % 3 != 0 || !RegExp(r'^\d+$').hasMatch(digits)) return null;
  final part = digits.substring(0, digits.length ~/ 3);
  return digits == part * 3 ? part : null;
}
