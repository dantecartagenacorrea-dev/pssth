import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/export_names.dart';
import '../domain/library_entry.dart';

/// Saca documentos de la biblioteca: por la hoja Compartir del sistema o a una
/// carpeta del aparato. Nada sale si la persona no lo pide.
class FileExport {
  const FileExport._();

  static const _channel = MethodChannel('lector/file_export');

  /// Abre la hoja Compartir con todos los documentos.
  static Future<void> share(List<LibraryEntry> entries) async {
    final paths = await _copies(entries);
    await _channel.invokeMethod<bool>('share', {'paths': paths});
  }

  /// Abre la hoja Compartir con un texto, para mandarlo a la app que se elija.
  static Future<void> shareText(String text) => _channel.invokeMethod<bool>('shareText', {'text': text});

  /// Guarda los documentos: en Android, en Descargas/PSSTH; en iPhone, donde
  /// elija la persona. Devuelve cuántos guardó (0 si canceló) o null si esta
  /// versión del sistema no lo permite.
  static Future<int?> save(List<LibraryEntry> entries) async {
    final paths = await _copies(entries);
    final saved = await _channel.invokeMethod<int>('save', {'paths': paths});
    return saved == null || saved < 0 ? null : saved;
  }

  /// Copias temporales con el nombre visible. temp_cleanup las borra al día.
  static Future<List<String>> _copies(List<LibraryEntry> entries) async {
    final present = [
      for (final e in entries)
        if (await File(e.storedPath).exists()) e,
    ];
    if (present.isEmpty) throw const FileSystemException('No se encontró el documento');
    final temp = await getTemporaryDirectory();
    final dir = await Directory('${temp.path}/compartir_${DateTime.now().millisecondsSinceEpoch}').create();
    final names = exportNames([for (final e in present) (name: e.name, storedPath: e.storedPath)]);
    return [
      for (var i = 0; i < present.length; i++) (await File(present[i].storedPath).copy('${dir.path}/${names[i]}')).path,
    ];
  }
}
