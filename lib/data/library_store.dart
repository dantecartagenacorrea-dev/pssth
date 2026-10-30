import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/library_entry.dart';

class LibraryStore {
  LibraryStore({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  LibraryData _data = LibraryData();
  late Directory _root;

  LibraryData get data => _data;
  Directory get root => _root;

  Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    await initAt(Directory('${docs.path}/library'));
  }

  /// Inicializa en un directorio concreto (pruebas).
  Future<void> initAt(Directory dir) async {
    _root = dir;
    if (!await _root.exists()) {
      await _root.create(recursive: true);
    }
    await _load();
  }

  File get _indexFile => File('${_root.path}/library.json');

  Future<void> _load() async {
    try {
      if (!await _indexFile.exists()) {
        _data = LibraryData();
        return;
      }
      final raw = jsonDecode(await _indexFile.readAsString());
      if (raw is Map<String, dynamic>) {
        _data = LibraryData.fromJson(raw);
      } else {
        await _keepDamaged();
        _data = LibraryData();
      }
    } catch (_) {
      await _keepDamaged();
      _data = LibraryData();
    }
  }

  /// Si la lista no se puede leer, se guarda aparte en vez de pisarla con una
  /// vacía: así los documentos se pueden recuperar.
  Future<void> _keepDamaged() async {
    try {
      if (await _indexFile.exists()) {
        await _indexFile.rename('${_root.path}/library.dañada.${DateTime.now().millisecondsSinceEpoch}.json');
      }
    } catch (_) {}
  }

  /// Se escribe en un archivo aparte y se cambia de una vez: si la app se
  /// cierra a mitad de camino, la lista anterior queda entera.
  /// De a uno: dos guardados a la vez (la posición de lectura y una pausa)
  /// compartían el archivo aparte y uno fallaba o lo dañaba.
  Future<void> _save() {
    final next = _saving.then((_) => _write());
    _saving = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _saving = Future.value();

  Future<void> _write() async {
    final tmp = File('${_indexFile.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(_data.toJson()), flush: true);
    await tmp.rename(_indexFile.path);
  }

  static const _imageExt = {'jpg', 'jpeg', 'png', 'heic', 'heif', 'webp', 'bmp', 'tif', 'tiff'};

  /// Tipo de documento según la extensión.
  static String kindFor(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final ext = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    if (ext == 'txt') return 'txt';
    if (ext == 'epub') return 'epub';
    if (ext == 'html' || ext == 'htm') return 'html';
    if (_imageExt.contains(ext)) return 'image';
    return 'pdf';
  }

  /// Copia el archivo a la biblioteca local. El original nunca se modifica.
  Future<LibraryEntry> importFile({
    required String originalName,
    required List<int> bytes,
    bool scanned = false,
  }) async {
    // Mismo nombre y mismo contenido: reutilizar la entrada y su progreso.
    for (final e in _data.entries) {
      if (e.name != originalName) continue;
      try {
        final f = File(e.storedPath);
        if (await f.exists() && await f.length() == bytes.length) {
          final existing = await f.readAsBytes();
          if (_sameBytes(existing, bytes)) {
            e.lastOpenedIso = DateTime.now().toIso8601String();
            _data.entries.remove(e);
            _data.entries.insert(0, e);
            await _save();
            return e;
          }
        }
      } catch (_) {}
    }
    final id = _newId();
    final kind = kindFor(originalName);
    final dot = originalName.lastIndexOf('.');
    final ext = dot < 0 ? (kind == 'pdf' ? 'pdf' : kind) : originalName.substring(dot + 1).toLowerCase();
    final stored = File('${_root.path}/$id.$ext');
    await stored.writeAsBytes(bytes, flush: true);
    final entry = LibraryEntry(
      id: id,
      name: originalName,
      storedPath: stored.path,
      pageCount: 0,
      totalChunks: 0,
      lastOpenedIso: DateTime.now().toIso8601String(),
      kind: kind,
      scanned: scanned,
    );
    _data.entries.removeWhere((e) => e.id == id);
    _data.entries.insert(0, entry);
    await _save();
    return entry;
  }

  /// Identificador por hora en milisegundos; al importar en lote dos archivos
  /// pueden caer en el mismo milisegundo, así que se avanza hasta uno libre.
  String _newId() {
    var n = _clock().millisecondsSinceEpoch;
    while (_data.entries.any((e) => e.id == '$n')) {
      n++;
    }
    return '$n';
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> upsert(LibraryEntry entry) async {
    _data.entries.removeWhere((e) => e.id == entry.id);
    _data.entries.insert(0, entry);
    await _save();
  }

  Future<void> updatePosition({
    required String id,
    required int pageIndex,
    required int chunkIndex,
    bool? finished,
  }) async {
    final match = _data.entries.where((e) => e.id == id);
    if (match.isEmpty) {
      return;
    }
    final entry = match.first;
    entry.pageIndex = pageIndex;
    entry.chunkIndex = chunkIndex;
    if (finished != null) {
      entry.finished = finished;
    }
    entry.lastOpenedIso = DateTime.now().toIso8601String();
    _data.entries.removeWhere((e) => e.id == id);
    _data.entries.insert(0, entry);
    await _save();
  }

  /// Idioma elegido a mano para el documento (null = automático).
  Future<void> setLanguage(String id, String? language) async {
    final match = _data.entries.where((e) => e.id == id);
    if (match.isEmpty) return;
    match.first.language = language;
    await _save();
  }

  Future<void> updateExtraction({
    required String id,
    required int pageCount,
    required int totalChunks,
  }) async {
    final match = _data.entries.where((e) => e.id == id);
    if (match.isEmpty) {
      return;
    }
    final entry = match.first;
    entry.pageCount = pageCount;
    entry.totalChunks = totalChunks;
    await _save();
  }

  Future<void> toggleFavorite(String id) async {
    final e = byId(id);
    if (e == null) return;
    e.favorite = !e.favorite;
    await _save();
  }

  /// Elimina de la biblioteca la copia local y todos sus datos asociados
  /// (texto, caché de OCR). El archivo original del usuario no se toca.
  Future<void> remove(String id) async {
    _data.entries.removeWhere((e) => e.id == id);
    await _save();
    try {
      await for (final f in _root.list()) {
        final name = f.uri.pathSegments.last;
        if (f is File && name.startsWith('$id.')) {
          await f.delete();
        }
      }
    } catch (_) {}
  }

  LibraryEntry? byId(String id) {
    final match = _data.entries.where((e) => e.id == id);
    return match.isEmpty ? null : match.first;
  }
}
