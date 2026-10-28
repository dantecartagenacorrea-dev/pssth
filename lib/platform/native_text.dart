import 'package:flutter/services.dart';

import '../domain/scanned_pdf.dart';
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
    double? minimumTextHeight,
  }) async {
    try {
      final text = await _channel.invokeMethod<String>('recognize', {
        'path': imagePath,
        'languages': languages,
        'languageCorrection': languageCorrection,
        'minimumTextHeight': ?minimumTextHeight,
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

  /// Líneas reconocidas con su lugar en la imagen (fracciones 0–1, desde
  /// arriba a la izquierda) y el tamaño de la imagen, para armar un PDF con el
  /// texto buscable encima de la foto.
  Future<({int width, int height, List<ScannedLine> lines})> recognizeLines(String imagePath) async {
    final Map<Object?, Object?>? raw;
    try {
      raw = await _channel.invokeMethod<Map<Object?, Object?>>('recognizeLines', {'path': imagePath});
    } on MissingPluginException {
      throw OcrUnavailable();
    }
    double n(Object? v) => (v as num?)?.toDouble() ?? 0;
    final lines = <ScannedLine>[
      for (final l in (raw?['lines'] as List<Object?>? ?? const []).whereType<Map<Object?, Object?>>())
        (
          text: '${l['text'] ?? ''}',
          left: n(l['left']),
          top: n(l['top']),
          width: n(l['width']),
          height: n(l['height']),
        ),
    ];
    return (width: (raw?['width'] as num?)?.toInt() ?? 0, height: (raw?['height'] as num?)?.toInt() ?? 0, lines: lines);
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
