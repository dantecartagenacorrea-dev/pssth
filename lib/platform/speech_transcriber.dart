import 'package:flutter/services.dart';

/// La transcripción local no está disponible en este dispositivo.
class TranscriptionUnavailable implements Exception {
  TranscriptionUnavailable([this.message = 'La transcripción sin conexión no está disponible en este dispositivo.']);
  final String message;
  @override
  String toString() => message;
}

/// Convierte una grabación en texto. Debe ser local: nunca enviar el audio fuera.
abstract class SpeechTranscriber {
  Future<bool> isAvailable({String locale = 'es-ES'});
  Future<String> transcribe(String audioPath, {String locale = 'es-ES'});
}

/// Reconocimiento del sistema (iOS: SFSpeechRecognizer con `requiresOnDeviceRecognition`).
class NativeSpeechTranscriber implements SpeechTranscriber {
  static const _channel = MethodChannel('lector/speech');

  @override
  Future<bool> isAvailable({String locale = 'es-ES'}) async {
    try {
      return (await _channel.invokeMethod<bool>('available', {'locale': locale})) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<String> transcribe(String audioPath, {String locale = 'es-ES'}) async {
    try {
      final text = await _channel.invokeMethod<String>('transcribe', {
        'path': audioPath,
        'locale': locale,
      });
      return (text ?? '').trim();
    } on MissingPluginException {
      throw TranscriptionUnavailable();
    } on PlatformException catch (e) {
      if (e.code == 'unavailable') throw TranscriptionUnavailable();
      throw TranscriptionUnavailable(e.message ?? 'No se pudo transcribir la grabación.');
    }
  }
}

/// Prueba cada transcriptor en orden (sistema → modelo instalado). Falla solo
/// si ninguno está disponible, con el mensaje del primero.
class CompositeTranscriber implements SpeechTranscriber {
  CompositeTranscriber(this.engines);
  final List<SpeechTranscriber> engines;

  @override
  Future<bool> isAvailable({String locale = 'es-ES'}) async {
    for (final e in engines) {
      if (await e.isAvailable(locale: locale)) return true;
    }
    return false;
  }

  @override
  Future<String> transcribe(String audioPath, {String locale = 'es-ES'}) async {
    TranscriptionUnavailable? first;
    for (final e in engines) {
      if (!await e.isAvailable(locale: locale)) continue;
      try {
        return await e.transcribe(audioPath, locale: locale);
      } on TranscriptionUnavailable catch (err) {
        first ??= err;
      }
    }
    throw first ??
        TranscriptionUnavailable(
          'No hay transcripción sin conexión en este dispositivo. Puedes instalarla en Voces y modelos.',
        );
  }
}
