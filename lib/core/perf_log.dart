import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Medición en un equipo real: se activa al compilar con --dart-define=MEDIR=true.
const kMedir = bool.fromEnvironment('MEDIR');

/// Anota un tiempo en el registro (en pruebas o al medir; nunca en la app normal).
void perfLog(String message) {
  // ignore: avoid_print
  if (kDebugMode || kMedir) print('[lector] $message');
}

/// Al medir: cada 2 s anota cuántos cuadros por segundo se dibujaron, cuántos
/// llegaron tarde (más de 16,7 ms) y cuánto tardó el peor en armarse (build)
/// y en pintarse (raster).
void startFrameStats() {
  if (!kMedir) return;
  var frames = 0, late = 0, worstBuild = 0, worstRaster = 0, sumTotal = 0;
  var since = DateTime.now();
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final t in timings) {
      final build = t.buildDuration.inMicroseconds, raster = t.rasterDuration.inMicroseconds;
      frames++;
      sumTotal += t.totalSpan.inMicroseconds;
      if (build > worstBuild) worstBuild = build;
      if (raster > worstRaster) worstRaster = raster;
      if (t.totalSpan.inMicroseconds > 16667) late++;
    }
    final now = DateTime.now();
    final secs = now.difference(since).inMilliseconds / 1000;
    if (secs < 2 || frames == 0) return;
    perfLog('cuadros: ${(frames / secs).round()}/s · tarde $late de $frames · '
        'peor build ${worstBuild ~/ 1000} ms · peor raster ${worstRaster ~/ 1000} ms · '
        'promedio ${sumTotal ~/ frames ~/ 1000} ms');
    frames = late = worstBuild = worstRaster = sumTotal = 0;
    since = now;
  });
}
