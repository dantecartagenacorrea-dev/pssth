import 'dart:convert';
import 'dart:io';

/// Diccionario local de pronunciación: texto escrito -> pronunciación deseada.
class PronunciationStore {
  PronunciationStore(this._file);
  final File _file;
  final Map<String, String> _entries = {};
  bool _loaded = false;

  Map<String, String> get entries => Map.unmodifiable(_entries);

  Future<Map<String, String>> load() async {
    if (_loaded) return entries;
    _loaded = true;
    try {
      if (await _file.exists()) {
        final json = jsonDecode(await _file.readAsString());
        if (json is Map) {
          json.forEach((k, v) {
            final key = '$k'.trim();
            if (key.isNotEmpty) _entries[key] = '$v';
          });
        }
      }
    } catch (_) {
      _entries.clear();
      // Se aparta el archivo dañado: el próximo guardado no lo pisa.
      try {
        await _file.rename('${_file.path}.dañado.${DateTime.now().millisecondsSinceEpoch}');
      } on FileSystemException {
        // no había archivo
      }
    }
    return entries;
  }

  Future<void> set(String written, String spoken) async {
    await load();
    final key = written.trim();
    if (key.isEmpty) return;
    _entries[key] = spoken.trim();
    await _save();
  }

  Future<void> remove(String written) async {
    await load();
    _entries.remove(written);
    await _save();
  }

  /// Deja exactamente [entries] (lo que quedó al sincronizar).
  Future<void> replaceAll(Map<String, String> entries) async {
    await load();
    _entries
      ..clear()
      ..addAll(entries);
    await _save();
  }

  /// De a uno y en un archivo aparte que se cambia de una vez: si la app se
  /// cierra a mitad de guardar, queda la lista anterior entera.
  Future<void> _save() {
    final next = _saving.then((_) async {
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(jsonEncode(_entries), flush: true);
      await tmp.rename(_file.path);
    });
    _saving = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<void> _saving = Future.value();
}
