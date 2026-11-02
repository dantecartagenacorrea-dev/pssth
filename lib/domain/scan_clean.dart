import 'dart:math' as math;
import 'dart:typed_data';

/// Tinta segura: mucho más oscura que el papel. Papel: casi tan claro como él.
const _strongInk = 0.55, _thinInk = 0.78, _weakInk = 0.85;

/// Trazo de tinta bien negra: una firma lo es; la sombra de una arruga, no.
const _blackInk = 0.4;

/// Color de tinta (azul de firma, rojo de sello): saturado y no tan claro como las
/// líneas del cuaderno, que también son de color.
const _inkSaturation = 0.22, _colorInk = 0.72;

/// Deja una hoja arrugada como una copia limpia: conserva la tinta, con letras
/// tenues enteras, y quita lo demás. Trabaja en grises, [paper] es el brillo del
/// papel en cada píxel y devuelve 1 byte por píxel.
///
/// Un trazo se conserva solo si tiene alguna parte bien oscura: la arruga es
/// clara en todo su largo, y la letra tenue no. Además se van las manchitas, lo
/// que toca el borde de la foto y lo chico de los márgenes, si no hay texto al lado.
Uint8List cleanDocumentPage(Uint8List lum, Uint8List paper, int w, int h) {
  final ratio = _ratios(lum, paper);
  final keep = _inkToKeep(ratio, Uint8List(w * h), w, h);
  return straightenLines(_grayOf(ratio, keep), w, h);
}

/// Lo mismo en color (3 bytes por píxel): firmas y sellos de color se quedan con
/// el suyo; lo demás, negro sobre blanco.
Uint8List cleanDocumentColor(Uint8List rgb, Uint8List lum, Uint8List paper, int w, int h) {
  final n = w * h;
  final ratio = _ratios(lum, paper);
  final colored = Uint8List(n);
  for (var i = 0, j = 0; i < n; i++, j += 3) {
    final r = rgb[j], g = rgb[j + 1], b = rgb[j + 2];
    final high = math.max(r, math.max(g, b)), low = math.min(r, math.min(g, b));
    if ((high - low) / 255 > _inkSaturation && ratio[i] < _colorInk) colored[i] = 1;
  }
  final keep = _inkToKeep(ratio, colored, w, h);
  final gray = _grayOf(ratio, keep);
  final red = Uint8List.fromList(gray), green = Uint8List.fromList(gray), blue = Uint8List.fromList(gray);
  for (var i = 0, j = 0; i < n; i++, j += 3) {
    if (keep[i] != _keptColor) continue;
    // El color de la tinta, sobre papel blanco.
    final scale = 255 / math.max(paper[i], 40);
    red[i] = (rgb[j] * scale).round().clamp(0, 255);
    green[i] = (rgb[j + 1] * scale).round().clamp(0, 255);
    blue[i] = (rgb[j + 2] * scale).round().clamp(0, 255);
  }
  final shifts = lineShifts(gray, w, h);
  final out = Uint8List(n * 3);
  final channels = [red, green, blue];
  for (var c = 0; c < 3; c++) {
    final moved = shifts == null ? channels[c] : _applyShifts(channels[c], w, h, shifts);
    for (var i = 0; i < n; i++) {
      out[i * 3 + c] = moved[i];
    }
  }
  return out;
}

const _keptInk = 1, _keptColor = 2;

/// Desde aquí el trazo ya es negro del todo.
const _blackAt = 0.42;

Float32List _ratios(Uint8List lum, Uint8List paper) {
  final ratio = Float32List(lum.length);
  for (var i = 0; i < lum.length; i++) {
    ratio[i] = lum[i] / math.max(paper[i], 40);
  }
  return ratio;
}

Uint8List _grayOf(Float32List ratio, Uint8List keep) {
  final out = Uint8List(ratio.length);
  for (var i = 0; i < ratio.length; i++) {
    if (keep[i] == 0) {
      out[i] = 255;
      continue;
    }
    // Un corte suave: el trazo fino o tenue no se rompe.
    final t = (ratio[i] - _blackAt) / (_weakInk - _blackAt);
    out[i] = (t.clamp(0.0, 1.0) * 255).round();
  }
  return out;
}

/// Cada píxel: 0 si se va, [_keptInk] si es tinta, [_keptColor] si es tinta de color.
Uint8List _inkToKeep(Float32List ratio, Uint8List colored, int w, int h) {
  final n = w * h;
  final seen = Uint8List(n);
  final keep = Uint8List(n);
  final stack = Int32List(n);
  final pixels = Int32List(n);
  var used = 0;
  final minArea = math.max(6, (w * h * 2e-6).round());
  final longMark = h * 0.04;
  final marginX = w * 0.04, marginY = h * 0.04;
  final smallMark = h * 0.03;
  // Lo chico del margen o del borde: se decide cuando ya se sabe dónde está el texto.
  final doubtful = <({int start, int count, int mark, int left, int top, int right, int bottom})>[];

  for (var seed = 0; seed < n; seed++) {
    if (seen[seed] != 0 || ratio[seed] >= _weakInk) continue;
    var top = 0;
    final start = used;
    var strong = false, thin = false;
    var black = 0, colorful = 0;
    var left = w, right = 0, up = h, down = 0;
    stack[top++] = seed;
    seen[seed] = 1;
    while (top > 0) {
      final i = stack[--top];
      pixels[used++] = i;
      final v = ratio[i];
      if (v < _strongInk) strong = true;
      if (v < _thinInk) thin = true;
      if (v < _blackInk) black++;
      colorful += colored[i];
      final x = i % w, y = i ~/ w;
      if (x < left) left = x;
      if (x > right) right = x;
      if (y < up) up = y;
      if (y > down) down = y;
      for (var dy = -1; dy <= 1; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= w) continue;
          final j = yy * w + xx;
          if (seen[j] == 0 && ratio[j] < _weakInk) {
            seen[j] = 1;
            stack[top++] = j;
          }
        }
      }
    }
    final count = used - start;
    final width = right - left + 1, height = down - up + 1;
    final biggest = math.max(width, height);
    final touchesEdge = left == 0 || up == 0 || right == w - 1 || down == h - 1;
    final isColor = colorful * 2 >= count;
    final mark = isColor ? _keptColor : _keptInk;
    // Larga y fina: una arruga se va; una firma, que es bien negra o de color, no.
    final isSignature = isColor || black * 5 >= count;
    final thinAndLong = biggest > longMark && count / (width * height) < 0.12 && !isSignature;
    // Un trazo fino (la «I», una coma) nunca llega a ser bien oscuro: si es corto,
    // se queda cuando tiene texto al lado. Una arruga corta casi no se ve.
    final thinStroke = !strong && !isColor && thin && biggest < smallMark;
    final dropped = (!strong && !thinStroke && !isColor) || count < minArea || thinAndLong;
    if (dropped || (touchesEdge && biggest >= smallMark)) {
      used = start; // no se guarda
      continue;
    }
    final inMargin = right < marginX || left > w - marginX || down < marginY || up > h - marginY;
    // Las marcas de un doblez en el margen son altas y angostas.
    final foldMark = inMargin && !isColor && height > width * 3;
    if (thinStroke || touchesEdge || foldMark || (inMargin && !isColor && biggest < smallMark)) {
      doubtful.add((start: start, count: count, mark: mark, left: left, top: up, right: right, bottom: down));
      continue;
    }
    for (var k = start; k < used; k++) {
      keep[pixels[k]] = mark;
    }
  }

  // Una letra pegada al margen tiene texto al lado y se queda; una mancha, no.
  final near = (h * 0.015).round();
  final sum = _inkSums(keep, w, h);
  for (final d in doubtful) {
    final x0 = math.max(0, d.left - near), x1 = math.min(w, d.right + near + 1);
    final y0 = math.max(0, d.top - near), y1 = math.min(h, d.bottom + near + 1);
    final stride = w + 1;
    final inside = sum[y1 * stride + x1] - sum[y0 * stride + x1] - sum[y1 * stride + x0] + sum[y0 * stride + x0];
    if (inside == 0) continue;
    for (var k = d.start; k < d.start + d.count; k++) {
      keep[pixels[k]] = d.mark;
    }
  }
  return keep;
}

/// Tabla de sumas para contar la tinta de un rectángulo de una sola vez.
Int32List _inkSums(Uint8List ink, int w, int h) {
  final stride = w + 1;
  final sum = Int32List(stride * (h + 1));
  for (var y = 0; y < h; y++) {
    var row = 0;
    for (var x = 0; x < w; x++) {
      if (ink[y * w + x] != 0) row++;
      sum[(y + 1) * stride + x + 1] = sum[y * stride + x + 1] + row;
    }
  }
  return sum;
}

/// Endereza los renglones que suben y bajan: cada zona de la hoja se ondula a su
/// manera, así que en cada una las franjas verticales se corren lo que haga falta
/// para que sus renglones coincidan. Si la hoja casi no tiene texto, o el arreglo
/// sería exagerado, no toca nada.
Uint8List straightenLines(Uint8List page, int w, int h) {
  final shifts = lineShifts(page, w, h);
  return shifts == null ? page : _applyShifts(page, w, h, shifts);
}

const _bands = 24;
const _zones = 9;

/// Cuánto correr cada franja en cada zona; null si no hay que tocar la hoja.
List<Float64List>? lineShifts(Uint8List page, int w, int h) {
  final bandWidth = w ~/ _bands;
  if (bandWidth < 8 || h < 200) return null;
  final zoneHeight = h ~/ _zones;
  final maxStep = math.max(4, h ~/ 200);
  final limit = h * 0.02;
  final zones = <Float64List>[];
  var moved = false;
  for (var z = 0; z < _zones; z++) {
    // Cada zona mira también media zona a cada lado: más renglones, menos dudas.
    final top = math.max(0, z * zoneHeight - zoneHeight ~/ 2);
    final bottom = math.min(h, (z + 1) * zoneHeight + zoneHeight ~/ 2);
    final shift = _zoneShifts(page, w, top, bottom, bandWidth, maxStep);
    if (shift == null || shift.any((s) => s.abs() > limit)) {
      zones.add(Float64List(_bands));
      continue;
    }
    if (shift.any((s) => s != 0)) moved = true;
    zones.add(shift);
  }
  return moved ? zones : null;
}

Float64List? _zoneShifts(Uint8List page, int w, int top, int bottom, int bandWidth, int maxStep) {
  final height = bottom - top;
  final zone = Uint8List.sublistView(page, top * w, bottom * w);
  final profiles = [for (var b = 0; b < _bands; b++) _inkProfile(zone, w, height, b * bandWidth, bandWidth)];
  final ink = [for (final p in profiles) p.fold<double>(0, (sum, v) => sum + v)];
  if (ink.where((v) => v > 0).length < _bands ~/ 2) return null;
  // Se compara con la franja que tiene más texto.
  var reference = _bands ~/ 2;
  for (var b = 0; b < _bands; b++) {
    if (ink[b] > ink[reference]) reference = b;
  }
  final shift = Float64List(_bands);
  for (var b = reference + 1; b < _bands; b++) {
    shift[b] = shift[b - 1] + _bestShift(profiles[reference], profiles[b], shift[b - 1].round(), maxStep);
  }
  for (var b = reference - 1; b >= 0; b--) {
    shift[b] = shift[b + 1] + _bestShift(profiles[reference], profiles[b], shift[b + 1].round(), maxStep);
  }
  final smooth = Float64List(_bands);
  for (var b = 0; b < _bands; b++) {
    final lo = math.max(0, b - 1), hi = math.min(_bands - 1, b + 1);
    var sum = 0.0;
    for (var k = lo; k <= hi; k++) {
      sum += shift[k];
    }
    smooth[b] = sum / (hi - lo + 1);
  }
  return smooth;
}

Uint8List _applyShifts(Uint8List page, int w, int h, List<Float64List> zones) {
  final bandWidth = w ~/ _bands;
  final zoneHeight = h / _zones;
  final out = Uint8List(w * h)..fillRange(0, w * h, 255);
  // Por columna: en qué franjas cae.
  final band0 = Int32List(w), band1 = Int32List(w);
  final mix = Float64List(w);
  for (var x = 0; x < w; x++) {
    final at = (x + 0.5) / bandWidth - 0.5;
    band0[x] = at.floor().clamp(0, _bands - 1);
    band1[x] = (band0[x] + 1).clamp(0, _bands - 1);
    mix[x] = (at - band0[x]).clamp(0.0, 1.0);
  }
  for (var y = 0; y < h; y++) {
    final at = (y + 0.5) / zoneHeight - 0.5;
    final z0 = at.floor().clamp(0, _zones - 1), z1 = (z0 + 1).clamp(0, _zones - 1);
    final t = (at - z0).clamp(0.0, 1.0);
    final a = zones[z0], b = zones[z1];
    for (var x = 0; x < w; x++) {
      final f = mix[x];
      final top = a[band0[x]] * (1 - f) + a[band1[x]] * f;
      final low = b[band0[x]] * (1 - f) + b[band1[x]] * f;
      final s = top * (1 - t) + low * t;
      final whole = s.floor();
      final part = s - whole;
      final from = y + whole;
      if (from < 0 || from >= h) continue;
      final v0 = page[from * w + x];
      final v1 = from + 1 < h ? page[(from + 1) * w + x] : v0;
      out[y * w + x] = (v0 * (1 - part) + v1 * part).round();
    }
  }
  return out;
}

Float64List _inkProfile(Uint8List page, int w, int h, int left, int width) {
  final raw = Float64List(h);
  for (var y = 0; y < h; y++) {
    var sum = 0;
    for (var x = left; x < left + width; x++) {
      sum += 255 - page[y * w + x];
    }
    raw[y] = sum.toDouble();
  }
  // Suavizado: los renglones se alinean por su forma, no por cada letra.
  const r = 3;
  final out = Float64List(h);
  var total = 0.0;
  for (var y = 0; y < h; y++) {
    total += raw[y];
    if (y > 2 * r) total -= raw[y - 2 * r - 1];
    if (y >= r) out[y - r] = total;
  }
  return out;
}

/// Cuánto más hay que correr [next] (ya corrido [base]) para coincidir con [ref].
int _bestShift(Float64List ref, Float64List next, int base, int maxStep) {
  var best = 0;
  var bestScore = -1.0;
  // El menor cambio gana en un empate: sin texto no se mueve nada.
  for (final s in [
    0,
    for (var k = 1; k <= maxStep; k++) ...[k, -k],
  ]) {
    var score = 0.0;
    final d = base + s;
    final lo = math.max(0, -d), hi = math.min(ref.length, next.length - d);
    for (var y = lo; y < hi; y++) {
      score += ref[y] * next[y + d];
    }
    if (score > bestScore) {
      bestScore = score;
      best = s;
    }
  }
  return best;
}

/// Qué tan nítida salió una foto: el contraste de sus bordes, de 0 a 1 respecto del
/// papel. El borde más fuerte de la tinta casi no depende de cuánto texto haya.
double pageSharpness(Uint8List lum, Uint8List paper, int w, int h) {
  final counts = Int32List(101);
  var total = 0;
  for (var y = 0; y < h; y += 2) {
    for (var x = 0; x + 1 < w; x++) {
      final i = y * w + x;
      final step = (lum[i + 1] - lum[i]).abs() / math.max(paper[i], 40);
      if (step < 0.05) continue; // papel: no es un borde
      counts[(step * 100).round().clamp(0, 100)]++;
      total++;
    }
  }
  if (total == 0) return 0;
  // El 10 % de los bordes más marcados.
  var left = (total * 0.1).ceil();
  for (var v = 100; v >= 0; v--) {
    left -= counts[v];
    if (left <= 0) return v / 100;
  }
  return 0;
}
