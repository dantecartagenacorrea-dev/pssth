class AppException implements Exception {
  AppException(this.message);
  final String message;

  @override
  String toString() => message;
}

const ocrInProgressMessage =
    'Reconociendo el texto de las páginas escaneadas… La lectura empezará en cuanto haya texto.';

const ocrNoTextMessage =
    'No se encontró texto legible en este documento. Si es un escaneo borroso o una foto, prueba con una imagen más nítida.';

const noSelectableTextMessage =
    'Este PDF no contiene texto reconocible. La lectura de documentos escaneados estará disponible posteriormente.';
