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

  Future<void> _save() => _file.writeAsString(jsonEncode(_entries), flush: true);
}
