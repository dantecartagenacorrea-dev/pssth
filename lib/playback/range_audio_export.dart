import 'dart:io';

import 'package:flutter/services.dart' show MethodChannel;

import '../core/app_exception.dart';
import '../data/wav_joiner.dart';

/// Escribe el audio de [path] (o de varias partes) y devuelve dónde quedó, o
/// null si la voz no permite guardar audio.
typedef RenderAudio = Future<String?> Function(String text, String path);

/// Junta frases seguidas en trozos de hasta [maxChars] (menos llamadas a la
/// voz) sin cortar ninguna frase.
List<String> exportPieces(List<String> sentences, {int maxChars = 600}) {
  final pieces = <String>[];
  final b = StringBuffer();
  for (final s in sentences) {
    if (b.isNotEmpty && b.length + 1 + s.length > maxChars) {
      pieces.add(b.toString());
      b.clear();
    }
    if (b.isNotEmpty) b.write(' ');
    b.write(s);
  }
  if (b.isNotEmpty) pieces.add(b.toString());
  return pieces;
}

const _channel = MethodChannel('lector/audio_export');

/// Arma un solo archivo de audio con [sentences] leídas por la voz activa:
/// trozo a trozo (sin tener todo en memoria), unidos y comprimidos a M4A.
/// [base] es la ruta sin extensión. Devuelve la ruta final (.m4a, o .wav si
/// no se pudo comprimir) o null si se canceló. Las partes se borran siempre.
Future<String?> exportSentencesAudio({
  required List<String> sentences,
  required String base,
  required RenderAudio render,
  void Function(double done)? onProgress,
  bool Function()? cancelled,
}) async {
  final pieces = exportPieces(sentences);
  if (pieces.isEmpty) return null;
  final joiner = WavJoiner('$base.wav');
  final others = <String>[]; // iOS con la voz del sistema escribe CAF
  var ok = false;
  try {
    for (var i = 0; i < pieces.length; i++) {
      if (cancelled?.call() ?? false) return null;
      final part = await render(pieces[i], '${base}_$i.wav');
      if (part == null) throw AppException('Esta voz no permite guardar audio. Elige otra voz e inténtalo de nuevo.');
      if (part.endsWith('.wav') && others.isEmpty) {
        await joiner.add(await File(part).readAsBytes());
        await _delete(part);
      } else if (joiner.dataBytes == 0) {
        others.add(part);
      } else {
        await _delete(part);
        throw AppException('La voz cambió mientras se preparaba el audio. Inténtalo de nuevo.');
      }
      onProgress?.call((i + 1) / pieces.length);
    }
    if (cancelled?.call() ?? false) return null;
    if (others.isNotEmpty) {
      final out = await _channel.invokeMethod<String>('joinToM4a', {'paths': others, 'out': '$base.m4a'});
      if (out == null || out.isEmpty) throw AppException('No se pudo preparar el audio.');
      ok = true;
      return out;
    }
    await joiner.close();
    String? m4a;
    try {
      m4a = await _channel.invokeMethod<String>('toM4a', {'path': '$base.wav', 'out': '$base.m4a'});
    } catch (_) {
      m4a = null; // sin compresor: queda el WAV
    }
    ok = true;
    if (m4a == null || m4a.isEmpty) return '$base.wav';
    await _delete('$base.wav');
    return m4a;
  } finally {
    await joiner.close();
    for (final p in others) {
      await _delete(p);
    }
    if (!ok) {
      await _delete('$base.wav');
      await _delete('$base.m4a');
    }
  }
}

Future<void> _delete(String path) async {
  try {
    await File(path).delete();
  } on FileSystemException {
    // ya no estaba
  }
}
