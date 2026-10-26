import 'dart:io';

import '../domain/library_entry.dart';
import 'library_store.dart';

/// Máximo de archivos que se importan de una vez.
const maxBatchFiles = 50;

const audioExtensions = {'wav', 'm4a', 'mp3', 'aac', 'caf'};

/// Archivo elegido por el usuario. [path] es null si el sistema no lo entregó.
class BatchFile {
  const BatchFile({required this.name, required this.path});

  final String name;
  final String? path;

  String get extension => name.contains('.') ? name.split('.').last.toLowerCase() : '';
  bool get isAudio => audioExtensions.contains(extension);
  String get title => extension.isEmpty ? name : name.substring(0, name.length - extension.length - 1);
}

class BatchImportResult {
  const BatchImportResult({
    required this.imported,
    required this.alreadyThere,
    required this.failed,
    required this.leftOut,
  });

  final int imported;
  final int alreadyThere;
  final List<String> failed;
  final int leftOut;

  String get summary {
    final total = imported + alreadyThere + failed.length;
    final parts = <String>['Se importaron $imported de $total.'];
    if (alreadyThere > 0) parts.add('Ya estaban en la biblioteca: $alreadyThere.');
    if (failed.isNotEmpty) {
      final names = failed.take(3).join(', ');
      final more = failed.length > 3 ? '…' : '';
      parts.add('No se pudieron importar ${failed.length}: $names$more.');
    }
    if (leftOut > 0) parts.add('Se importan hasta $maxBatchFiles por vez; quedaron fuera $leftOut.');
    return parts.join(' ');
  }
}

/// Transcribe un audio y lo guarda en la biblioteca como documento.
typedef AudioImporter = Future<LibraryEntry> Function(String path, String title);

/// Importa un lote a la biblioteca sin abrir nada. Los documentos van primero
/// (es solo copiarlos); los audios después, uno tras otro, porque transcribir
/// tarda. Un archivo que falla se anota y el lote sigue.
Future<BatchImportResult> importBatch({
  required List<BatchFile> files,
  required LibraryStore store,
  required AudioImporter importAudio,
  void Function(int index, int total, BatchFile file)? onProgress,
}) async {
  final chosen = files.take(maxBatchFiles).toList();
  final ordered = [...chosen.where((f) => !f.isAudio), ...chosen.where((f) => f.isAudio)];
  var imported = 0;
  var alreadyThere = 0;
  final failed = <String>[];
  for (var i = 0; i < ordered.length; i++) {
    final file = ordered[i];
    onProgress?.call(i + 1, ordered.length, file);
    final path = file.path;
    try {
      if (path == null) throw const FileSystemException('sin ruta');
      if (file.isAudio) {
        await importAudio(path, file.title);
        imported++;
        continue;
      }
      // Se lee uno por uno para no cargar todo el lote en memoria.
      final bytes = await File(path).readAsBytes();
      if (bytes.isEmpty) throw FileSystemException('vacío', path);
      final before = store.data.entries.map((e) => e.id).toSet();
      final entry = await store.importFile(originalName: file.name, bytes: bytes);
      if (before.contains(entry.id)) {
        alreadyThere++;
      } else {
        imported++;
      }
    } on Exception {
      failed.add(file.name);
    }
  }
  return BatchImportResult(
    imported: imported,
    alreadyThere: alreadyThere,
    failed: failed,
    leftOut: files.length - chosen.length,
  );
}
