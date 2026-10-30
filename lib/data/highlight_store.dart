import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/highlight.dart';

/// Subrayados y notas de todos los documentos, en un JSON local.
class HighlightStore {
  HighlightStore(this._file);
  final File _file;
  final List<Highlight> _all = [];
  Future<void>? _loading;

  /// La que usa la app (se crea al iniciar, como la cola de modelos).
  static HighlightStore? instance;

  /// Cambia con cada alta, nota o borrado: la lectura vuelve a marcar.
  final ValueNotifier<int> changes = ValueNotifier(0);

  Future<void> _load() => _loading ??= _read();

  Future<void> _read() async {
    try {
      if (await _file.exists()) {
        final json = jsonDecode(await _file.readAsString());
        if (json is List) {
          _all.addAll(
            json
                .whereType<Map>()
                .map((e) => Highlight.fromJson(Map<String, dynamic>.from(e)))
                .where((h) => h.id.isNotEmpty && h.documentId.isNotEmpty),
          );
        }
      }
    } catch (_) {
      _all.clear();
      // Se aparta el archivo dañado: el próximo guardado no lo pisa.
      try {
        await _file.rename('${_file.path}.dañado.${DateTime.now().millisecondsSinceEpoch}');
      } on FileSystemException {
        // no había archivo
      }
    }
    changes.value++;
  }

  /// De a uno y en un archivo aparte que se cambia de una vez (como los
  /// marcadores): dos cambios seguidos no mezclan el JSON.
  Future<void> _save() {
    changes.value++;
    final next = _saving.then((_) async {
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode(_all.map((h) => h.toJson()).toList()), flush: true);
      await tmp.rename(_file.path);
    });
    _saving = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _saving = Future.value();

  /// ¿Está subrayada esa frase? Falso mientras no se haya leído el archivo.
  bool isMarked(String documentId, int pageIndex, int chunkIndex) {
    if (_loading == null) _load();
    return _find(documentId, pageIndex, chunkIndex) != null;
  }

  Highlight? _find(String documentId, int pageIndex, int chunkIndex) {
    for (final h in _all) {
      if (h.documentId == documentId && h.pageIndex == pageIndex && h.chunkIndex == chunkIndex) return h;
    }
    return null;
  }

  Future<Highlight?> find(String documentId, int pageIndex, int chunkIndex) async {
    await _load();
    return _find(documentId, pageIndex, chunkIndex);
  }

  Future<List<Highlight>> forDocument(String documentId) async {
    await _load();
    return _all.where((h) => h.documentId == documentId).toList()..sort((a, b) {
      final p = a.pageIndex.compareTo(b.pageIndex);
      return p != 0 ? p : a.chunkIndex.compareTo(b.chunkIndex);
    });
  }

  /// Subraya la frase (si ya lo estaba, devuelve la existente).
  Future<Highlight> add({
    required String documentId,
    required int pageIndex,
    required int chunkIndex,
    required String text,
    String note = '',
  }) async {
    await _load();
    final existing = _find(documentId, pageIndex, chunkIndex);
    if (existing != null) return existing;
    final h = Highlight(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      documentId: documentId,
      pageIndex: pageIndex,
      chunkIndex: chunkIndex,
      text: text,
      note: note,
      createdIso: DateTime.now().toIso8601String(),
    );
    _all.add(h);
    await _save();
    return h;
  }

  Future<void> setNote(String id, String note) async {
    await _load();
    final i = _all.indexWhere((h) => h.id == id);
    if (i < 0) return;
    _all[i] = _all[i].withNote(note.trim());
    await _save();
  }

  Future<void> remove(String id) async {
    await _load();
    _all.removeWhere((h) => h.id == id);
    await _save();
  }

  Future<void> removeAllFor(String documentId) async {
    await _load();
    _all.removeWhere((h) => h.documentId == documentId);
    await _save();
  }
}
