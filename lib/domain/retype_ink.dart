import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'scanned_pdf.dart' show ScannedLine;

/// Una firma, sello o dibujo recortado de la foto, sobre blanco. El lugar y el
/// tamaño van de 0 a 1 de la hoja.
typedef PageMark = ({Uint8List jpeg, double left, double top, double boxWidth, double boxHeight});

/// Lo que la foto dice además del texto: qué palabras de cada renglón van en
/// negrita (null: no se pudo medir), lo que no es texto y qué renglones eran parte
/// de un sello: ya van en su recorte.
typedef PageInk = ({List<List<bool>?> bold, List<PageMark> marks, Set<int> stamps});

const PageInk noInk = (bold: [], marks: [], stamps: <int>{});

/// Tinta: más oscura que esta fracción del papel que la rodea.
const _inkShare = 0.6, _tintedInkShare = 0.88;
const _inkSaturation = 0.22;
const _coloredShare = 0.3;

/// Con menos trazos un renglón no dice hacia dónde se inclina.
const _minToFit = 5;

/// Un renglón es algo más alto que su letra típica.
const _lineOverLetter = 1.4;

/// Tanto más gruesa que la palabra típica de la hoja ya es negrita.
const _boldAbove = 1.25, _boldBeside = 1.12;

/// Hasta este largo una palabra tiene muy pocos trazos para decidir sola.
const _shortWord = 2;

/// Con menos palabras no hay con qué comparar; con un trazo más fino que esto, en
/// píxeles, la foto no alcanza para distinguir el grosor.
const _minWords = 8;
const _minStroke = 2.4;

/// Medidas de un manchón, en altos de renglón.
const _tallBlob = 2.5, _speck = 0.3, _clusterGap = 1.5;
const _bigStroke = 3.0, _ringShape = 3.0;

/// Un sello ocupa como mucho esta fracción del ancho de la hoja; una firma, la otra.
const _ringMaxWidth = 0.4, _markMaxWidth = 0.7;

/// Un renglón va con el sello solo si la mayoría de sus trazos entró en el recorte.
const _stampMajority = 0.7;

/// Tanta tinta suelta ya no es un documento: es ruido, y se deja de buscar.
const _maxRuns = 1500000, _maxLoose = 6000;
const _markMinHeight = 1.5, _markMinWidth = 2.5, _markMinInk = 0.5;

/// Las arrugas son sombras claras; una firma o un sello tienen tinta de verdad.
const _markMaxDarkness = 0.5;

/// A esta fracción del borde ya es el fondo o el canto de la hoja.
const _edgeZone = 0.005;

class _Blob {
  _Blob(this.minX, this.maxX, this.minY, this.maxY);
  int minX, maxX, minY, maxY;
  int area = 0, edge = 0, colored = 0;
  double darkness = 0;
  final runs = <int>[];

  int get width => maxX - minX + 1;
  int get height => maxY - minY + 1;
  double get centerX => (minX + maxX) / 2;
  double get centerY => (minY + maxY) / 2;
}

/// Lee la tinta de la foto. [rgb]: 3 bytes por píxel; [lum] y [paper]: brillo de
/// cada píxel y del papel a su alrededor. [lines]: el texto ya leído de la hoja.
PageInk readPageInk(Uint8List rgb, Uint8List lum, Uint8List paper, int w, int h, List<ScannedLine> lines) {
  if (lines.isEmpty) return noInk;
  final runY = <int>[], runX0 = <int>[], runX1 = <int>[];
  final blobs = _blobs(rgb, lum, paper, w, h, runY, runX0, runX1);
  if (!lines.any((l) => l.height > 0)) return noInk;
  final owners = _ownersOf(blobs, lines, w, h);
  final lineHeight = _letterHeight(blobs, owners);

  final inLine = List.generate(lines.length, (_) => <_Blob>[]);
  final loose = <_Blob>[];
  for (final (i, blob) in blobs.indexed) {
    final tall = blob.height > _tallBlob * lineHeight;
    if (owners[i] >= 0 && !tall) {
      inLine[owners[i]].add(blob);
    } else if (math.max(blob.width, blob.height) >= _speck * lineHeight) {
      loose.add(blob);
    }
  }
  // Un renglón de color puede ser parte de un sello, salvo que la hoja esté escrita
  // con esa tinta.
  final tinted = [
    for (var i = 0; i < lines.length; i++)
      if (_isTinted(inLine[i])) i,
  ];
  final stampBlobs = <_Blob, int>{};
  void takeForStamp(int line) {
    for (final blob in inLine[line]) {
      stampBlobs[blob] = line;
    }
    loose.addAll(inLine[line]);
  }

  if (tinted.length * 2 <= lines.length) tinted.forEach(takeForStamp);
  // Y en cualquier tinta, lo escrito dentro de un círculo o un marco cerrado.
  final rings = [
    for (final b in loose)
      if (_mayEnclose(b, lineHeight) && b.width <= _ringMaxWidth * w) b,
  ];
  for (var i = 0; i < lines.length; i++) {
    if (inLine[i].isEmpty || stampBlobs.containsValue(i)) continue;
    final x = inLine[i].fold<double>(0, (sum, b) => sum + b.centerX) / inLine[i].length;
    final y = inLine[i].fold<double>(0, (sum, b) => sum + b.centerY) / inLine[i].length;
    if (rings.any((ring) => _encloses(ring, x, y, runY, runX0, runX1))) takeForStamp(i);
  }
  final found = loose.length > _maxLoose
      ? (marks: const <PageMark>[], used: const <_Blob>{})
      : _marks(loose, lineHeight, rgb, paper, w, h, runY, runX0, runX1);
  // Un renglón que no entró en un recorte es texto común.
  final taken = <int, int>{};
  for (final blob in found.used) {
    final line = stampBlobs[blob];
    if (line != null) taken[line] = (taken[line] ?? 0) + 1;
  }
  final stamps = {
    for (final MapEntry(key: line, value: count) in taken.entries)
      if (count >= _stampMajority * inLine[line].length) line,
  };
  final boldWords = _boldWords(lines, [
    for (final (i, blobs) in inLine.indexed) stamps.contains(i) ? const <_Blob>[] : blobs,
  ]);
  return (bold: boldWords, marks: found.marks, stamps: stamps);
}

bool _mayEnclose(_Blob b, double lineHeight) {
  final wide = math.max(b.width, b.height), narrow = math.min(b.width, b.height);
  return narrow > _bigStroke * lineHeight && wide <= _ringShape * narrow;
}

/// ¿El trazo rodea al punto por los cuatro lados?
bool _encloses(_Blob ring, double x, double y, List<int> runY, List<int> runX0, List<int> runX1) {
  if (x < ring.minX || x > ring.maxX || y < ring.minY || y > ring.maxY) return false;
  final row = y.round();
  var left = false, right = false, above = false, below = false;
  for (final id in ring.runs) {
    if (runY[id] == row) {
      if (runX1[id] <= x) left = true;
      if (runX0[id] > x) right = true;
    }
    if (runX0[id] <= x && x < runX1[id]) {
      if (runY[id] < y) above = true;
      if (runY[id] > y) below = true;
    }
  }
  return left && right && above && below;
}

bool _isTinted(List<_Blob> blobs) {
  final area = blobs.fold<int>(0, (sum, b) => sum + b.area);
  return area > 0 && blobs.fold<int>(0, (sum, b) => sum + b.colored) >= _coloredShare * area;
}

/// Las negritas del renglón después de corregirlo: si cambió la cantidad de
/// palabras se reconocen por su texto.
List<bool>? boldAfterEdit(String original, String edited, List<bool>? bold) {
  if (bold == null) return null;
  final before = _wordsOf(original), after = _wordsOf(edited);
  if (before.length != bold.length) return null;
  if (before.length == after.length) return bold;
  final strong = {
    for (var i = 0; i < before.length; i++)
      if (bold[i]) before[i],
  };
  return [for (final word in after) strong.contains(word)];
}

List<String> _wordsOf(String text) => [
  for (final word in text.trim().split(RegExp(r'\s+')))
    if (word.isNotEmpty) word,
];

/// Junta los trazos de tinta que se tocan, renglón por renglón de píxeles.
List<_Blob> _blobs(
  Uint8List rgb,
  Uint8List lum,
  Uint8List paper,
  int w,
  int h,
  List<int> runY,
  List<int> runX0,
  List<int> runX1,
) {
  final ink = Uint8List(w * h);
  for (var i = 0; i < ink.length; i++) {
    if (lum[i] < _inkShare * paper[i]) {
      ink[i] = 1;
      continue;
    }
    // Un sello rojo es casi tan claro como el papel, pero se distingue por el color.
    if (lum[i] < _tintedInkShare * paper[i] && _isColored(rgb, i * 3)) ink[i] = 1;
  }
  final parent = <int>[];
  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  var previousStart = 0, previousEnd = 0;
  for (var y = 0; y < h; y++) {
    if (runY.length > _maxRuns) return const [];
    final start = runY.length;
    final row = y * w;
    var x = 0;
    var cursor = previousStart;
    while (x < w) {
      if (ink[row + x] == 0) {
        x++;
        continue;
      }
      final x0 = x;
      while (x < w && ink[row + x] == 1) {
        x++;
      }
      final id = runY.length;
      runY.add(y);
      runX0.add(x0);
      runX1.add(x);
      parent.add(id);
      while (cursor < previousEnd && runX1[cursor] < x0) {
        cursor++;
      }
      for (var c = cursor; c < previousEnd && runX0[c] <= x; c++) {
        final a = find(c), b = find(id);
        if (a != b) parent[b] = a;
      }
    }
    previousStart = start;
    previousEnd = runY.length;
  }

  final byRoot = <int, _Blob>{};
  for (var id = 0; id < runY.length; id++) {
    final y = runY[id], row = y * w;
    final blob = byRoot.putIfAbsent(find(id), () => _Blob(runX0[id], runX1[id] - 1, y, y));
    blob.minX = math.min(blob.minX, runX0[id]);
    blob.maxX = math.max(blob.maxX, runX1[id] - 1);
    blob.maxY = y;
    blob.runs.add(id);
    for (var x = runX0[id]; x < runX1[id]; x++) {
      final i = row + x;
      blob.area++;
      blob.darkness += lum[i] / math.max(paper[i], 1);
      if (_touchesPaper(ink, i, x, y, w, h)) blob.edge++;
      if (_isColored(rgb, i * 3)) blob.colored++;
    }
  }
  return byRoot.values.toList();
}

bool _isColored(Uint8List rgb, int j) {
  final low = math.min(rgb[j], math.min(rgb[j + 1], rgb[j + 2]));
  final high = math.max(rgb[j], math.max(rgb[j + 1], rgb[j + 2]));
  return (high - low) / 255 > _inkSaturation;
}

bool _touchesPaper(Uint8List ink, int i, int x, int y, int w, int h) {
  if (x == 0 || y == 0 || x == w - 1 || y == h - 1) return true;
  return ink[i - w - 1] == 0 ||
      ink[i - w] == 0 ||
      ink[i - w + 1] == 0 ||
      ink[i - 1] == 0 ||
      ink[i + 1] == 0 ||
      ink[i + w - 1] == 0 ||
      ink[i + w] == 0 ||
      ink[i + w + 1] == 0;
}

/// A qué renglón pertenece cada trazo (-1: a ninguno). En una hoja torcida las cajas
/// de los renglones se pisan: por eso se sigue la inclinación de cada uno.
List<int> _ownersOf(List<_Blob> blobs, List<ScannedLine> lines, int w, int h) {
  final fits = [for (final l in lines) (at: (l.top + l.height / 2) * h, slope: 0.0)];
  final owners = List<int>.filled(blobs.length, -1);
  for (var pass = 0; pass < 3; pass++) {
    final members = List.generate(lines.length, (_) => <_Blob>[]);
    for (final (i, blob) in blobs.indexed) {
      var best = -1;
      var nearest = double.infinity;
      for (final (j, l) in lines.indexed) {
        if (!_inBox(blob, l, w, h)) continue;
        final distance = (blob.centerY - (fits[j].at + fits[j].slope * blob.centerX)).abs();
        if (distance < nearest) {
          nearest = distance;
          best = j;
        }
      }
      owners[i] = best;
      if (best >= 0) members[best].add(blob);
    }
    for (final (j, group) in members.indexed) {
      if (group.length >= _minToFit) fits[j] = _fit(group);
    }
  }
  return owners;
}

bool _inBox(_Blob blob, ScannedLine l, int w, int h) {
  if (l.height == 0) return false;
  final x = blob.centerX / w, y = blob.centerY / h;
  final air = l.height * 0.15;
  return y >= l.top - air && y <= l.top + l.height + air && x >= l.left - air && x <= l.left + l.width + air;
}

({double at, double slope}) _fit(List<_Blob> blobs) {
  final n = blobs.length;
  final meanX = blobs.fold<double>(0, (sum, b) => sum + b.centerX) / n;
  final meanY = blobs.fold<double>(0, (sum, b) => sum + b.centerY) / n;
  var cross = 0.0, spread = 0.0;
  for (final b in blobs) {
    cross += (b.centerX - meanX) * (b.centerY - meanY);
    spread += (b.centerX - meanX) * (b.centerX - meanX);
  }
  final slope = spread == 0 ? 0.0 : cross / spread;
  return (at: meanY - slope * meanX, slope: slope);
}

/// El alto de renglón real, en píxeles: las cajas de una hoja torcida son más altas.
double _letterHeight(List<_Blob> blobs, List<int> owners) {
  final heights = [
    for (final (i, blob) in blobs.indexed)
      if (owners[i] >= 0) blob.height,
  ]..sort();
  return heights.isEmpty ? 1.0 : math.max(heights[heights.length ~/ 2] * _lineOverLetter, 1.0);
}

/// Reparte los trazos de cada renglón entre sus palabras, cortando por los huecos
/// más grandes, y compara el grosor de cada palabra con el típico de la hoja.
List<List<bool>?> _boldWords(List<ScannedLine> lines, List<List<_Blob>> inLine) {
  final strokes = <List<double>?>[];
  for (var i = 0; i < lines.length; i++) {
    strokes.add(_wordStrokes(_wordsOf(lines[i].text).length, inLine[i]));
  }
  final all = [
    for (final line in strokes)
      if (line != null)
        for (final s in line)
          if (s > 0) s,
  ]..sort();
  if (all.length < _minWords || all[all.length ~/ 2] < _minStroke) {
    return List<List<bool>?>.filled(lines.length, null);
  }
  final typical = all[all.length ~/ 2];
  return [
    for (final (i, line) in strokes.indexed)
      line == null ? null : _boldOfLine(_wordsOf(lines[i].text), [for (final s in line) s / typical]),
  ];
}

/// Lo bien grueso es negrita, salvo las palabritas sueltas, que miden mal. Lo algo
/// grueso pegado a una negrita también: la tinta de un mismo tramo se gasta parejo.
List<bool> _boldOfLine(List<String> words, List<double> ratios) {
  final bold = [for (final (i, ratio) in ratios.indexed) ratio >= _boldAbove && words[i].length > _shortWord];
  for (var i = 1; i < bold.length; i++) {
    if (bold[i - 1] && ratios[i] >= _boldBeside) bold[i] = true;
  }
  for (var i = bold.length - 2; i >= 0; i--) {
    if (bold[i + 1] && ratios[i] >= _boldBeside) bold[i] = true;
  }
  return bold;
}

/// El grosor de cada palabra (0 si es pura puntuación); null si no alcanzan los trazos.
List<double>? _wordStrokes(int words, List<_Blob> blobs) {
  if (words == 0 || blobs.length < words) return null;
  final sorted = [...blobs]..sort((a, b) => a.minX.compareTo(b.minX));
  final gaps = <(int, int)>[];
  var reach = sorted.first.maxX;
  for (var i = 1; i < sorted.length; i++) {
    gaps.add((sorted[i].minX - reach, i));
    reach = math.max(reach, sorted[i].maxX);
  }
  gaps.sort((a, b) => b.$1.compareTo(a.$1));
  final cuts = [for (final g in gaps.take(words - 1)) g.$2]..sort();
  final tallest = sorted.map((b) => b.height).reduce(math.max);
  final out = <double>[];
  var from = 0;
  for (final end in [...cuts, sorted.length]) {
    var area = 0, edge = 0;
    for (final blob in sorted.sublist(from, end)) {
      // Puntos, comas y tildes son demasiado chicos para medir el trazo.
      if (blob.height < 0.4 * tallest) continue;
      area += blob.area;
      edge += blob.edge;
    }
    out.add(edge == 0 ? 0 : 2 * area / edge);
    from = end;
  }
  return out;
}

({List<PageMark> marks, Set<_Blob> used}) _marks(
  List<_Blob> loose,
  double lineHeight,
  Uint8List rgb,
  Uint8List paper,
  int w,
  int h,
  List<int> runY,
  List<int> runX0,
  List<int> runX1,
) {
  final inside = [
    for (final b in loose)
      if (b.minX > _edgeZone * w &&
          b.maxX < (1 - _edgeZone) * w &&
          b.minY > _edgeZone * h &&
          b.maxY < (1 - _edgeZone) * h)
        b,
  ];
  final out = <PageMark>[];
  final used = <_Blob>{};
  for (final found in _clusters(inside, _clusterGap * lineHeight)) {
    final group = _withoutStrayLetters(found, lineHeight);
    if (group.isEmpty) continue;
    final minX = group.map((b) => b.minX).reduce(math.min), maxX = group.map((b) => b.maxX).reduce(math.max);
    final minY = group.map((b) => b.minY).reduce(math.min), maxY = group.map((b) => b.maxY).reduce(math.max);
    final area = group.fold<int>(0, (sum, b) => sum + b.area);
    final colored = group.fold<int>(0, (sum, b) => sum + b.colored);
    final darkness = group.fold<double>(0, (sum, b) => sum + b.darkness) / math.max(area, 1);
    if (maxY - minY + 1 < _markMinHeight * lineHeight || maxX - minX + 1 < _markMinWidth * lineHeight) continue;
    if (area < _markMinInk * lineHeight * lineHeight) continue;
    if (darkness > _markMaxDarkness && colored < _coloredShare * area) continue;
    // La cuadrícula de una tabla o el marco de un formulario no son una firma.
    if (colored < _coloredShare * area && maxX - minX + 1 > _markMaxWidth * w) continue;
    used.addAll(group);
    out.add(_crop(group, minX, maxX, minY, maxY, rgb, paper, w, h, runY, runX0, runX1));
  }
  out.sort((a, b) => a.top.compareTo(b.top));
  return (marks: out, used: used);
}

/// Una letra negra suelta junto a una firma es del texto, que ya va escrito. Dentro
/// del trazo grande (un sello con letras) se queda.
List<_Blob> _withoutStrayLetters(List<_Blob> group, double lineHeight) {
  final big = [
    for (final b in group)
      if (b.width > _bigStroke * lineHeight || b.height > _bigStroke * lineHeight) b,
  ];
  // Puras letras negras: es texto que el lector no ubicó, no una firma.
  if (big.isEmpty) {
    return [
      for (final b in group)
        if (b.colored >= _coloredShare * b.area) b,
    ];
  }
  bool inside(_Blob b) =>
      big.any((o) => b.centerX >= o.minX && b.centerX <= o.maxX && b.centerY >= o.minY && b.centerY <= o.maxY);
  return [
    for (final b in group)
      if (big.contains(b) || b.colored >= _coloredShare * b.area || inside(b)) b,
  ];
}

/// Junta los manchones cercanos: una firma son varios trazos sueltos.
List<List<_Blob>> _clusters(List<_Blob> blobs, double gap) {
  final parent = List<int>.generate(blobs.length, (i) => i);
  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  // De izquierda a derecha: lo que empieza más allá del alcance ya no puede tocarse.
  final order = List<int>.generate(blobs.length, (i) => i)..sort((a, b) => blobs[a].minX.compareTo(blobs[b].minX));
  for (var i = 0; i < order.length; i++) {
    final a = blobs[order[i]];
    for (var j = i + 1; j < order.length && blobs[order[j]].minX - a.maxX <= gap; j++) {
      if (_distance(a, blobs[order[j]]) <= gap) parent[find(order[j])] = find(order[i]);
    }
  }
  final groups = <int, List<_Blob>>{};
  for (var i = 0; i < blobs.length; i++) {
    groups.putIfAbsent(find(i), () => []).add(blobs[i]);
  }
  return groups.values.toList();
}

double _distance(_Blob a, _Blob b) {
  final dx = math.max(0, math.max(a.minX - b.maxX, b.minX - a.maxX));
  final dy = math.max(0, math.max(a.minY - b.maxY, b.minY - a.maxY));
  return math.max(dx, dy).toDouble();
}

/// Solo la tinta del grupo, con su color, sobre blanco: lo demás del recorte (el
/// texto que ya va escrito, las arrugas) no pasa.
PageMark _crop(
  List<_Blob> group,
  int minX,
  int maxX,
  int minY,
  int maxY,
  Uint8List rgb,
  Uint8List paper,
  int w,
  int h,
  List<int> runY,
  List<int> runX0,
  List<int> runX1,
) {
  const air = 3;
  final x0 = math.max(0, minX - air), y0 = math.max(0, minY - air);
  final x1 = math.min(w - 1, maxX + air), y1 = math.min(h - 1, maxY + air);
  final cw = x1 - x0 + 1, ch = y1 - y0 + 1;
  final keep = Uint8List(cw * ch);
  // Un poco más que la tinta: el borde suave del trazo también va.
  for (final blob in group) {
    for (final id in blob.runs) {
      final y = runY[id];
      for (var yy = math.max(y0, y - 2); yy <= math.min(y1, y + 2); yy++) {
        final row = (yy - y0) * cw;
        for (var x = math.max(x0, runX0[id] - 2); x <= math.min(x1, runX1[id] + 1); x++) {
          keep[row + x - x0] = 1;
        }
      }
    }
  }
  final out = img.Image(width: cw, height: ch);
  for (var y = 0; y < ch; y++) {
    for (var x = 0; x < cw; x++) {
      if (keep[y * cw + x] == 0) {
        out.setPixelRgb(x, y, 255, 255, 255);
        continue;
      }
      final i = (y + y0) * w + x + x0;
      final bright = 255 / math.max(paper[i], 1);
      out.setPixelRgb(
        x,
        y,
        math.min(255, (rgb[i * 3] * bright).round()),
        math.min(255, (rgb[i * 3 + 1] * bright).round()),
        math.min(255, (rgb[i * 3 + 2] * bright).round()),
      );
    }
  }
  return (jpeg: img.encodeJpg(out, quality: 90), left: x0 / w, top: y0 / h, boxWidth: cw / w, boxHeight: ch / h);
}
