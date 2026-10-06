class AppException implements Exception {
  AppException(this.message);
  final String message;

  @override
  String toString() => message;
}

const noSelectableTextMessage =
    'Este PDF no contiene texto reconocible. La lectura de documentos escaneados estará disponible posteriormente.';
