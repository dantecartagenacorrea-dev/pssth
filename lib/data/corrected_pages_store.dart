import 'dart:convert';
import 'dart:io';

/// Páginas ya corregidas por la IA local, por documento (`<id>.ia.json` junto
/// al documento: se borra con él). Así no se vuelve a corregir al reabrirlo.
/// Si cambia el modelo, lo guardado no se reutiliza.
class CorrectedPagesStore {
  CorrectedPagesStore(this.root);

  final Directory root;

  File _file(String id) => File('${root.path}/$id.ia.json');

  Future<Map<int, String>> load(String id, {required String model}) async {
    try {
      final f = _file(id);
      if (!await f.exists()) return {};
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map || raw['model'] != model || raw['pages'] is! Map) return {};
      return {
        for (final e in (raw['pages'] as Map).entries)
          if (int.tryParse('${e.key}') != null && e.value is String) int.parse('${e.key}'): e.value as String,
      };
    } on FormatException {
      return {};
    } on FileSystemException {
      return {};
    }
  }

  Future<void> save(String id, {required String model, required Map<int, String> pages}) async {
    await _file(id).writeAsString(jsonEncode({
      'model': model,
      'pages': {for (final e in pages.entries) '${e.key}': e.value},
    }));
  }
}
