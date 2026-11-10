import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'retype_ink.dart';
import 'scan_clean.dart';
import 'scanned_pdf.dart';

/// Una línea del formulario, ya recta, en fracciones de la imagen. [weight]: su
/// grosor, en fracción del lado que la atraviesa.
typedef FormRule = ({double x0, double y0, double x1, double y1, double weight});

/// Lo que va debajo del texto: la tinta que no es texto ni línea, con 255 de fondo,
/// y las líneas, ya niveladas. [blank]: no quedó tinta. [tilt]: cuánto bajaba la
/// hoja de izquierda a derecha (fracción del alto por fracción del ancho).
typedef FormLayer = ({Uint8List gray, List<FormRule> rules, bool blank, double tilt});

/// La capa ya lista para el PDF; [jpeg] es null si no quedó tinta.
typedef FormPageLayer = ({Uint8List? jpeg, List<FormRule> rules, double tilt});

/// Una hoja para rearmar con su mismo formato.
typedef FormPage = ({ScannedPage page, PageInk ink, FormPageLayer layer});

/// Tinta de una línea: más oscura que esta fracción del papel.
const _ruleInk = 0.72;

/// Parte del tramo que tiene que ser tinta para contar como línea.
const _tileFill = 0.85;

/// Largo mínimo de una línea, en fracción del lado: las horizontales más, porque
/// los trazos de las letras también lo son.
const _minHorizontal = 0.06, _minVertical = 0.03;

class _Dash {
  _Dash(this.tile, this.center, this.thick);
  final int tile;
  final double center;
  final int thick;
}

class _Chain {
  _Chain(_Dash first) : dashes = [first];
  final List<_Dash> dashes;
  late int start, end;
  double get center => dashes.map((d) => d.center).reduce((a, b) => a + b) / dashes.length;
  double get thick => dashes.map((d) => d.thick).reduce((a, b) => a + b) / dashes.length;
}

/// Encuentra las líneas largas y rectas de la foto. Se mide por tramos cortos para
/// que una línea algo torcida siga siendo una sola y una zona negra no cuente.
List<_Chain> _chains(Uint8List ink, int along, int across, double minShare) {
  final tile = math.max(8, (along * 0.012).round());
  final maxThick = math.max(7, (across * 0.005).round());
  final minLength = along * minShare;
  final chains = <_Chain>[];
  final open = <_Chain>[];
  final counts = Int32List(across);
  for (var t = 0; (t + 1) * tile <= along; t++) {
    counts.fillRange(0, across, 0);
    for (var b = 0; b < across; b++) {
      final row = b * along;
      for (var a = t * tile; a < (t + 1) * tile; a++) {
        counts[b] += ink[row + a];
      }
    }
    final needed = (tile * _tileFill).ceil();
    open.removeWhere((c) => c.dashes.last.tile < t - 2);
    for (var b = 0; b < across; b++) {
      if (counts[b] < needed) continue;
      final first = b;
      while (b + 1 < across && counts[b + 1] >= needed) {
        b++;
      }
      final thick = b - first + 1;
      if (thick > maxThick) continue;
      final dash = _Dash(t, (first + b) / 2, thick);
      _Chain? chain;
      for (final c in open) {
        if (c.dashes.last.tile < t && (c.dashes.last.center - dash.center).abs() <= 3) chain = c;
      }
      if (chain == null) {
        final made = _Chain(dash);
        open.add(made);
        chains.add(made);
      } else {
        chain.dashes.add(dash);
      }
    }
  }
  final found = <_Chain>[];
  for (final c in chains) {
    if ((c.dashes.last.tile - c.dashes.first.tile + 1) * tile < minLength) continue;
    c.start = _reach(ink, along, c.dashes.first.tile * tile - 1, c.dashes.first.center, across, -1);
    c.end = _reach(ink, along, (c.dashes.last.tile + 1) * tile, c.dashes.last.center, across, 1);
    found.add(c);
  }
  return found;
}

/// Hasta dónde sigue la tinta desde [from]: la punta real de la línea, que los
/// tramos cortos no alcanzan.
int _reach(Uint8List ink, int along, int from, double center, int across, int step) {
  var last = from - step;
  final b0 = math.max(0, center.round() - 2), b1 = math.min(across - 1, center.round() + 2);
  var misses = 0;
  for (var a = from; a >= 0 && a < along && misses <= 3; a += step) {
    var hit = false;
    for (var b = b0; b <= b1 && !hit; b++) {
      hit = ink[b * along + a] != 0;
    }
    if (hit) {
      last = a;
      misses = 0;
    } else {
      misses++;
    }
  }
  return last;
}

Uint8List _transposed(Uint8List source, int w, int h) {
  final out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      out[x * h + y] = source[y * w + x];
    }
  }
  return out;
}

Uint8List _inkOf(Uint8List lum, Uint8List paper) {
  final ink = Uint8List(lum.length);
  for (var i = 0; i < lum.length; i++) {
    if (lum[i] < _ruleInk * math.max(paper[i], 40)) ink[i] = 1;
  }
  return ink;
}

double _overlap(double a0, double a1, double b0, double b1) => math.min(a1, b1) - math.max(a0, b0);

/// ¿Es un trazo de letra? Las líneas de un formulario pasan entre los renglones.
bool _isTextStroke(FormRule r, List<ScannedLine> lines) {
  var crossed = 0.0, tallest = 0.0;
  for (final l in lines) {
    if (l.width <= 0 || l.height <= 0) continue;
    if (r.y0 == r.y1) {
      final inBody = r.y0 > l.top + l.height * 0.2 && r.y0 < l.top + l.height * 0.8;
      if (inBody && _overlap(r.x0, r.x1, l.left, l.left + l.width) > (r.x1 - r.x0) * 0.5) return true;
    } else {
      final inside = r.x0 > l.left && r.x0 < l.left + l.width;
      final over = _overlap(r.y0, r.y1, l.top, l.top + l.height);
      if (!inside || over <= 0) continue;
      if (over > (r.y1 - r.y0) * 0.7) return true;
      crossed += over;
      tallest = math.max(tallest, l.height);
    }
  }
  // Letras alineadas de dos o tres renglones seguidos parecen una rayita. Un
  // divisor de tabla es más largo, aunque el lector junte sus columnas.
  return crossed > (r.y1 - r.y0) * 0.5 && r.y1 - r.y0 < tallest * _maxStrokeRows;
}

const _maxStrokeRows = 5;

/// Hasta esta distancia (fracción de la hoja) una vertical y una horizontal se tocan.
const _joinReach = 0.02;

/// Más juntas que esto (fracción de la hoja) no hay líneas de formulario: un
/// cuaderno rayado las tiene a casi el 3 %.
const _denseGap = 0.012;

/// Tantas vecinas así de juntas son una trama (muaré de pantalla, tela, rejilla).
/// Una sola es un borde doble, que sí puede tener un formulario.
const _denseCount = 2;

/// Dos rayas paralelas a menos de esto, una sobre otra, son la misma.
const _sameRule = 0.006;

/// Quita las rayas que son trama y las repetidas. true si la hoja tenía trama.
bool _dropTexture(List<FormRule> rules) {
  bool vertical(FormRule r) => r.x0 == r.x1;
  double at(FormRule r) => vertical(r) ? r.x0 : r.y0;
  (double, double) span(FormRule r) => vertical(r) ? (r.y0, r.y1) : (r.x0, r.x1);
  double shared(FormRule a, FormRule b) {
    final (a0, a1) = span(a);
    final (b0, b1) = span(b);
    return math.min(a1, b1) - math.max(a0, b0);
  }

  bool alongside(FormRule a, FormRule b, double gap) =>
      !identical(a, b) &&
      vertical(a) == vertical(b) &&
      (at(a) - at(b)).abs() < gap &&
      shared(a, b) > 0.5 * math.min(span(a).$2 - span(a).$1, span(b).$2 - span(b).$1);

  final texture = {
    for (final r in rules)
      if (rules.where((o) => alongside(r, o, _denseGap)).length >= _denseCount) r,
  };
  // Las de la orilla de la trama tienen menos vecinas, pero son parte de ella.
  for (var grew = true; grew;) {
    final edge = [
      for (final r in rules)
        if (!texture.contains(r) && texture.any((t) => alongside(r, t, _denseGap))) r,
    ];
    texture.addAll(edge);
    grew = edge.isNotEmpty;
  }
  rules.removeWhere(texture.contains);
  // De dos casi encimadas queda la más larga.
  final repeated = <FormRule>{};
  for (final r in rules) {
    if (repeated.contains(r)) continue;
    for (final o in rules) {
      if (repeated.contains(o) || !alongside(r, o, _sameRule)) continue;
      final longer = (span(r).$2 - span(r).$1) >= (span(o).$2 - span(o).$1);
      repeated.add(longer ? o : r);
      if (!longer) break;
    }
  }
  rules.removeWhere(repeated.contains);
  return texture.isNotEmpty;
}

/// Un punto del fondo más chico que esto (fracción del ancho) no es un trazo:
/// una letra mide al menos el doble, una casilla, mucho más.
const _speck = 0.004;

/// Más oscuro que esto, en la capa de fondo, cuenta como parte de algo.
const _speckInk = 160;

/// Quita los puntitos sueltos que deja una trama o el polvo.
void _dropSpecks(Uint8List gray, int w, int h) {
  final limit = math.max(3, (w * _speck).round());
  final seen = Uint8List(w * h);
  final stack = <int>[], part = <int>[];
  for (var seed = 0; seed < w * h; seed++) {
    if (seen[seed] != 0 || gray[seed] >= _speckInk) continue;
    seen[seed] = 1;
    stack.add(seed);
    part.clear();
    var left = w, right = 0, up = h, down = 0;
    while (stack.isNotEmpty) {
      final i = stack.removeLast();
      part.add(i);
      final x = i % w, y = i ~/ w;
      left = math.min(left, x);
      right = math.max(right, x);
      up = math.min(up, y);
      down = math.max(down, y);
      for (var dy = -1; dy <= 1; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= w) continue;
          final j = yy * w + xx;
          if (seen[j] == 0 && gray[j] < _speckInk) {
            seen[j] = 1;
            stack.add(j);
          }
        }
      }
    }
    if (right - left + 1 > limit || down - up + 1 > limit) continue;
    for (final i in part) {
      gray[i] = 255;
    }
  }
}

/// Margen a los costados del texto y las líneas donde todavía puede haber algo.
const _sideReach = 0.03;

/// A los costados, más allá del texto y de las líneas, solo queda la sombra del
/// borde del papel o de la mesa: se borra del fondo.
void _clearSides(Uint8List gray, int w, int h, List<ScannedLine> lines, List<FormRule> rules) {
  final read = [
    for (final l in lines)
      if (l.text.trim().isNotEmpty && l.width > 0) l,
  ];
  if (read.isEmpty) return;
  var left = read.map((l) => l.left).reduce(math.min);
  var right = read.map((l) => l.left + l.width).reduce(math.max);
  for (final r in rules) {
    left = math.min(left, r.x0);
    right = math.max(right, r.x1);
  }
  final x0 = ((left - _sideReach) * w).floor(), x1 = ((right + _sideReach) * w).ceil();
  if (x0 > 0) _whiten(gray, w, h, 0, 0, x0 - 1, h - 1);
  if (x1 < w) _whiten(gray, w, h, x1, 0, w - 1, h - 1);
}

/// Más claro que esto, en lo que queda de fondo, no es tinta: es una arruga.
const _faintResidue = 190;

void _whiten(Uint8List gray, int w, int h, int x0, int y0, int x1, int y1) {
  final left = math.max(0, x0), right = math.min(w - 1, x1);
  for (var y = math.max(0, y0); y <= math.min(h - 1, y1); y++) {
    gray.fillRange(y * w + left, y * w + right + 1, 255);
  }
}

/// Separa la hoja en capas: las líneas se redibujan rectas, el texto se escribe
/// de nuevo, y todo lo demás (casillas, logos, lo que no se leyó) queda limpio
/// donde estaba, para que nada se pierda.
FormLayer formLayerFrom(
  Uint8List lum,
  Uint8List paper,
  int w,
  int h,
  List<ScannedLine> lines,
  List<PageMark> marks,
) {
  final gray = cleanInkOnly(lum, paper, w, h);
  final ink = _inkOf(lum, paper);
  final rules = <FormRule>[];
  final across = _chains(ink, w, h, _minHorizontal);
  final slope = _slopeOf(across, math.max(8, (w * 0.012).round()), w);
  final tilt = slope * w / h;
  for (final c in across) {
    final y = (c.center + 0.5) / h;
    final rule = (x0: c.start / w, y0: y, x1: (c.end + 1) / w, y1: y, weight: c.thick / h);
    if (_isTextStroke(rule, lines)) continue;
    rules.add(rule);
    final tile = math.max(8, (w * 0.012).round());
    for (final d in c.dashes) {
      final pad = (d.thick / 2).ceil() + 2;
      final from = math.max(c.start, d.tile * tile - tile), to = math.min(c.end, (d.tile + 2) * tile);
      _whiten(gray, w, h, from, d.center.round() - pad, to, d.center.round() + pad);
    }
    final ends = (c.dashes.first, c.dashes.last);
    final pad = (ends.$1.thick / 2).ceil() + 2;
    _whiten(gray, w, h, c.start, ends.$1.center.round() - pad, ends.$1.tile * tile, ends.$1.center.round() + pad);
    _whiten(gray, w, h, ends.$2.tile * tile, ends.$2.center.round() - pad, c.end, ends.$2.center.round() + pad);
  }
  final flipped = _transposed(ink, w, h);
  final tile = math.max(8, (h * 0.012).round());
  for (final c in _chains(flipped, h, w, _minVertical)) {
    final x = (c.center + 0.5) / w;
    final rule = (x0: x, y0: c.start / h, x1: x, y1: (c.end + 1) / h, weight: c.thick / w);
    if (_isTextStroke(rule, lines)) continue;
    rules.add(rule);
    for (final d in c.dashes) {
      final pad = (d.thick / 2).ceil() + 2;
      final from = math.max(c.start, d.tile * tile - tile), to = math.min(c.end, (d.tile + 2) * tile);
      _whiten(gray, w, h, d.center.round() - pad, from, d.center.round() + pad, to);
    }
    final pad = (c.dashes.first.thick / 2).ceil() + 2;
    final at = c.center.round();
    _whiten(gray, w, h, at - pad, c.start, at + pad, c.dashes.first.tile * tile);
    _whiten(gray, w, h, at - pad, c.dashes.last.tile * tile, at + pad, c.end);
  }
  final textured = _dropTexture(rules);
  // Una raya vertical que ninguna horizontal toca no arma una tabla: es el borde
  // o un doblez del papel. No se dibuja, y ya quedó fuera de la capa de fondo.
  final flat = [
    for (final r in rules)
      if (r.y0 == r.y1) r,
  ];
  bool joined(FormRule v) => flat.any(
    (a) =>
        v.x0 >= a.x0 - _joinReach &&
        v.x0 <= a.x1 + _joinReach &&
        a.y0 >= v.y0 - _joinReach &&
        a.y0 <= v.y1 + _joinReach,
  );
  // En una hoja con trama, además, tiene que ir de una horizontal a otra: si un
  // extremo cuelga en el aire, es trama. En una hoja normal una esquina en L vale.
  bool touches(FormRule v, double y) => flat.any(
    (a) => v.x0 >= a.x0 - _joinReach && v.x0 <= a.x1 + _joinReach && (a.y0 - y).abs() <= _joinReach,
  );
  rules.removeWhere(
    (r) => r.x0 == r.x1 && (textured ? !(touches(r, r.y0) && touches(r, r.y1)) : !joined(r)),
  );
  for (final l in lines) {
    if (l.text.trim().isEmpty || l.width <= 0 || l.height <= 0) continue;
    final padX = w * 0.003, padY = l.height * h * 0.15;
    _whiten(
      gray,
      w,
      h,
      (l.left * w - padX).floor(),
      (l.top * h - padY).floor(),
      ((l.left + l.width) * w + padX).ceil(),
      ((l.top + l.height) * h + padY).ceil(),
    );
  }
  for (final m in marks) {
    _whiten(
      gray,
      w,
      h,
      (m.left * w).floor(),
      (m.top * h).floor(),
      ((m.left + m.boxWidth) * w).ceil(),
      ((m.top + m.boxHeight) * h).ceil(),
    );
  }
  for (var i = 0; i < gray.length; i++) {
    if (gray[i] > _faintResidue) gray[i] = 255;
  }
  _clearSides(gray, w, h, lines, rules);
  if (textured) _dropSpecks(gray, w, h);
  return (
    gray: _sheared(gray, w, h, slope),
    rules: _snapCorners([for (final r in rules) _levelRule(r, tilt)]),
    blank: !gray.any((v) => v < 200),
    tilt: tilt,
  );
}

/// Inclinación de la hoja: la mediana de sus líneas largas, en píxeles por píxel.
/// Una inclinación mayor que [_maxSlope] (unos 7°, lo más que se llegan a encadenar
/// los tramos de una línea) no es la hoja torcida sino un error.
const _maxSlope = 0.12;

double _slopeOf(List<_Chain> chains, int tile, int w) {
  final slopes = <double>[];
  for (final c in chains) {
    final tiles = c.dashes.last.tile - c.dashes.first.tile;
    if (tiles * tile < w * 0.2) continue;
    slopes.add((c.dashes.last.center - c.dashes.first.center) / (tiles * tile));
  }
  if (slopes.isEmpty) return 0;
  slopes.sort();
  final median = slopes[slopes.length ~/ 2];
  return median.abs() > _maxSlope ? 0 : median;
}

/// Lo que sube o baja un punto al nivelar, según dónde esté de izquierda a derecha.
double _lift(double tilt, double x) => tilt * (x - 0.5);

FormRule _levelRule(FormRule r, double tilt) => r.y0 == r.y1
    ? () {
        final y = r.y0 - _lift(tilt, (r.x0 + r.x1) / 2);
        return (x0: r.x0, y0: y, x1: r.x1, y1: y, weight: r.weight);
      }()
    : (x0: r.x0, y0: r.y0 - _lift(tilt, r.x0), x1: r.x1, y1: r.y1 - _lift(tilt, r.x1), weight: r.weight);

/// La capa con cada columna subida o bajada, para que quede a nivel con lo demás.
Uint8List _sheared(Uint8List gray, int w, int h, double slope) {
  if (slope == 0) return gray;
  final out = Uint8List(w * h)..fillRange(0, w * h, 255);
  for (var x = 0; x < w; x++) {
    final shift = (slope * (x - w / 2)).round();
    for (var y = math.max(0, shift); y < math.min(h, h + shift); y++) {
      out[(y - shift) * w + x] = gray[y * w + x];
    }
  }
  return out;
}

/// Cuánto puede faltar o sobrar para que dos líneas se consideren una esquina.
const _cornerReach = 0.008;

/// Lleva la punta [end] hasta la línea que la cruza, sobre el eje medido, si la hay.
double _snapped(double end, double position, Iterable<({double at, double from, double to})> crossing) {
  for (final c in crossing) {
    final meets = position >= c.from - _cornerReach && position <= c.to + _cornerReach;
    if (meets && (c.at - end).abs() <= _cornerReach) return c.at;
  }
  return end;
}

/// Una hoja algo torcida deja las esquinas con puntitas o sin cerrar: cada línea
/// termina justo en la que la cruza.
List<FormRule> _snapCorners(List<FormRule> rules) {
  final vertical = [
    for (final r in rules)
      if (r.x0 == r.x1) (at: r.x0, from: r.y0, to: r.y1),
  ];
  final horizontal = [
    for (final r in rules)
      if (r.y0 == r.y1) (at: r.y0, from: r.x0, to: r.x1),
  ];
  return [
    for (final r in rules)
      if (r.y0 == r.y1)
        (x0: _snapped(r.x0, r.y0, vertical), y0: r.y0, x1: _snapped(r.x1, r.y0, vertical), y1: r.y1, weight: r.weight)
      else
        (x0: r.x0, y0: _snapped(r.y0, r.x0, horizontal), x1: r.x1, y1: _snapped(r.y1, r.x0, horizontal), weight: r.weight),
  ];
}

/// Tamaño de letra para un renglón sin caja medida.
double _usualHeight(List<ScannedLine> lines) {
  final heights = [
    for (final l in lines)
      if (l.height > 0) l.height,
  ]..sort();
  return heights.isEmpty ? 0.015 : heights[heights.length ~/ 2];
}

/// Hasta aquí de diferencia es el mismo tamaño de letra mal medido; más, es un
/// título o una nota al pie de verdad.
const _sameSize = 0.35;

/// Hueco entre palabras que se acepta para llenar el renglón, en espacios.
const _minGap = 0.5, _maxGap = 4.0;

double _fitSize(ScannedLine line, PdfFont font, double w, double h, double usual) {
  final natural = font.stringMetrics(latin1Safe(line.text).trim()).advanceWidth;
  final size = (line.height > 0 ? line.height : usual) * h * 0.82;
  return line.width > 0 && natural > 0 ? math.min(size, line.width * w / natural) : size;
}

/// El tamaño de letra del cuerpo de la hoja: el más común de sus renglones.
double _bodySize(List<ScannedLine> lines, PdfFont font, double w, double h, double usual) {
  final sizes = [
    for (final l in lines)
      if (l.text.trim().isNotEmpty) _fitSize(l, font, w, h, usual),
  ]..sort();
  return sizes.isEmpty ? 12 : sizes[sizes.length ~/ 2];
}

void _drawLine(
  PdfGraphics canvas,
  ScannedLine line,
  List<bool>? bold,
  ({
    PdfFont regular,
    PdfFont bold,
    double left,
    double top,
    double w,
    double h,
    double pageH,
    double usual,
    double body,
  })
  at,
) {
  final words = latin1Safe(line.text).trim().split(RegExp(r'\s+'));
  final flags = bold != null && bold.length == words.length ? bold : null;
  final space = at.regular.stringMetrics(' ').advanceWidth;
  PdfFont fontOf(int i) => flags != null && flags[i] ? at.bold : at.regular;
  var inked = 0.0;
  for (var i = 0; i < words.length; i++) {
    inked += fontOf(i).stringMetrics(words[i]).advanceWidth;
  }
  final gaps = words.length - 1;
  final boxHeight = (line.height > 0 ? line.height : at.usual) * at.h;
  final width = line.width * at.w;
  // Un mismo cuerpo de letra en toda la hoja, como salió de la impresora.
  var size = _fitSize(line, at.regular, at.w, at.h, at.usual);
  if ((size - at.body).abs() <= at.body * _sameSize) size = at.body;
  // Si no entra ni con los huecos justos, se achica este renglón.
  if (width > 0 && inked + _minGap * space * gaps > 0) {
    size = math.min(size, width / (inked + _minGap * space * gaps));
  }
  size = size.clamp(4.0, 72.0);
  // Los huecos llenan el ancho medido: el renglón termina donde terminaba.
  var gap = space * size;
  if (width > 0 && gaps > 0) {
    final filled = (width - inked * size) / gaps;
    if (filled >= _minGap * space * size && filled <= _maxGap * space * size) gap = filled;
  }
  var x = at.left + line.left * at.w;
  final baseline = at.pageH - (at.top + line.top * at.h + boxHeight * 0.8);
  for (var i = 0; i < words.length; i++) {
    final font = fontOf(i);
    canvas.drawString(font, size, words[i], x, baseline);
    x += font.stringMetrics(words[i]).advanceWidth * size + gap;
  }
}

/// Arma el documento recién impreso con el mismo formato de cada hoja: cada texto
/// en su lugar, las líneas rectas y las firmas donde estaban. Una hoja en la que no
/// se leyó nada va con su foto: nunca se pierde.
Future<Uint8List> buildFormPdf(
  List<FormPage> pages, {
  String? title,
  bool compress = true,
  ScanPaper paper = ScanPaper.carta,
}) {
  final doc = pw.Document(title: title, creator: 'PSSTH!', compress: compress);
  final regular = PdfFont.helvetica(doc.document);
  final bold = PdfFont.helveticaBold(doc.document);
  final sheet = paper.format ?? PdfPageFormat.letter;
  for (final form in pages) {
    final page = form.page;
    final fit = math.min(sheet.width / page.width, sheet.height / page.height);
    final w = page.width * fit, h = page.height * fit;
    final format = paper.format ?? PdfPageFormat(w, h);
    final left = (format.width - w) / 2, top = (format.height - h) / 2;
    final hasText = page.lines.any((l) => l.text.trim().isNotEmpty);
    final layer = form.layer.jpeg;
    final usual = _usualHeight(page.lines);
    doc.addPage(
      pw.Page(
        pageFormat: format,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Stack(
          children: [
            if (!hasText)
              pw.Positioned(left: left, top: top, child: pw.Image(pw.MemoryImage(page.jpeg), width: w, height: h))
            else ...[
              if (layer != null)
                pw.Positioned(left: left, top: top, child: pw.Image(pw.MemoryImage(layer), width: w, height: h)),
              pw.CustomPaint(
                size: PdfPoint(format.width, format.height),
                painter: (canvas, size) {
                  canvas.setStrokeColor(PdfColors.black);
                  for (final r in form.layer.rules) {
                    final across = r.y0 == r.y1 ? h : w;
                    canvas
                      ..setLineWidth(math.max(0.5, r.weight * across))
                      ..drawLine(
                        left + r.x0 * w,
                        size.y - (top + r.y0 * h),
                        left + r.x1 * w,
                        size.y - (top + r.y1 * h),
                      )
                      ..strokePath();
                  }
                  canvas.setFillColor(PdfColors.black);
                  final at = (
                    regular: regular,
                    bold: bold,
                    left: left,
                    top: top,
                    w: w,
                    h: h,
                    pageH: size.y,
                    usual: usual,
                    body: _bodySize(page.lines, regular, w, h, usual),
                  );
                  for (final (i, l) in page.lines.indexed) {
                    if (l.text.trim().isEmpty) continue;
                    final top = l.top - _lift(form.layer.tilt, l.left + l.width / 2);
                    final line = (text: l.text, left: l.left, top: top, width: l.width, height: l.height);
                    _drawLine(canvas, line, i < form.ink.bold.length ? form.ink.bold[i] : null, at);
                  }
                },
              ),
              for (final m in form.ink.marks)
                pw.Positioned(
                  left: left + m.left * w,
                  top: top + (m.top - _lift(form.layer.tilt, m.left + m.boxWidth / 2)) * h,
                  child: pw.Image(pw.MemoryImage(m.jpeg), width: m.boxWidth * w, height: m.boxHeight * h),
                ),
            ],
          ],
        ),
      ),
    );
  }
  return doc.save();
}
