class OcrUnavailable implements Exception {
  OcrUnavailable([this.reason = 'OCR no disponible en este dispositivo.']);
  final String reason;
  @override
  String toString() => reason;
}

/// Motor OCR intercambiable. La implementación por defecto usa Apple Vision
/// (local, gratuito, offline).
abstract class OcrEngine {
  Future<bool> isAvailable();

  /// Reconoce el texto de una imagen en disco. [languages]: etiquetas BCP-47
  /// preferidas (p. ej. 'es-ES'); vacío = automático.
  Future<String> recognize(String imagePath, {List<String> languages});
}
