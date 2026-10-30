import 'dart:convert';
import 'dart:io';

import '../domain/bookmark.dart';

class BookmarkStore {
  BookmarkStore(this._file);
  final File _file;
  final List<Bookmark> _all = [];
  bool _loaded = false;

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      if (await _file.exists()) {
        final json = jsonDecode(await _file.readAsString());
        if (json is List) {
          _all.addAll(
            json
                .whereType<Map>()
                .map((e) => Bookmark.fromJson(Map<String, dynamic>.from(e)))
                .where((b) => b.id.isNotEmpty && b.documentId.isNotEmpty),
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
  }

  /// De a uno y en un archivo aparte que se cambia de una vez: dos cambios
  /// seguidos mezclaban el JSON y, al no poder leerlo, se perdían todos.
  Future<void> _save() {
    final next = _saving.then((_) async {
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode(_all.map((b) => b.toJson()).toList()), flush: true);
      await tmp.rename(_file.path);
    });
    _saving = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _saving = Future.value();

  Future<List<Bookmark>> forDocument(String documentId) async {
    await _load();
    final list = _all.where((b) => b.documentId == documentId).toList()
      ..sort((a, b) {
        final p = a.pageIndex.compareTo(b.pageIndex);
        return p != 0 ? p : a.chunkIndex.compareTo(b.chunkIndex);
      });
    return list;
  }

  Future<Bookmark> add({
    required String documentId,
    required int pageIndex,
    required int chunkIndex,
    required String label,
  }) async {
    await _load();
    final existing = _all.where(
      (b) => b.documentId == documentId && b.pageIndex == pageIndex && b.chunkIndex == chunkIndex,
    );
    if (existing.isNotEmpty) return existing.first;
    final b = Bookmark(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      documentId: documentId,
      pageIndex: pageIndex,
      chunkIndex: chunkIndex,
      label: label.length > 80 ? '${label.substring(0, 80)}…' : label,
      createdIso: DateTime.now().toIso8601String(),
    );
    _all.add(b);
    await _save();
    return b;
  }

  Future<void> remove(String id) async {
    await _load();
    _all.removeWhere((b) => b.id == id);
    await _save();
  }

  Future<void> removeAllFor(String documentId) async {
    await _load();
    _all.removeWhere((b) => b.documentId == documentId);
    await _save();
  }
}
