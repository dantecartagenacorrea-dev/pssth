import 'package:flutter/services.dart';

import '../ocr/ocr_engine.dart';

/// Puente con las capacidades nativas de iOS (Vision y NaturalLanguage).
/// En plataformas sin implementación nativa devuelve "no disponible".
class NativeText implements OcrEngine {
  static const _channel = MethodChannel('lector/native_text');

  @override
  Future<bool> isAvailable() async {
    try {
      return (await _channel.invokeMethod<bool>('available')) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<String> recognize(
    String imagePath, {
    List<String> languages = const [],
    bool languageCorrection = true,
  }) async {
    try {
      final text = await _channel.invokeMethod<String>('recognize', {
        'path': imagePath,
        'languages': languages,
        'languageCorrection': languageCorrection,
      });
      return text ?? '';
    } on MissingPluginException {
      throw OcrUnavailable();
    }
  }

  /// Contenido de los códigos QR de la imagen; vacío si no hay o no se puede.
  Future<List<String>> barcodes(String imagePath) async {
    try {
      final codes = await _channel.invokeMethod<List<Object?>>('barcodes', {'path': imagePath});
      return (codes ?? const []).whereType<String>().toList();
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// Idioma dominante ('es', 'en', ...) o null.
  Future<String?> detectLanguage(String text) async {
    try {
      return await _channel.invokeMethod<String>('detectLanguage', {
        'text': text,
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Pide permiso para usar la voz personal del usuario (iOS 17+, creada por él
  /// en Ajustes → Accesibilidad → Voz personal). Devuelve si quedó autorizada.
  Future<bool> requestPersonalVoice() async {
    try {
      return (await _channel.invokeMethod<bool>('requestPersonalVoice')) ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
