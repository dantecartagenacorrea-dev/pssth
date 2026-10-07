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
