import 'dart:convert';
import 'dart:io';

/// Caché local del OCR: página -> texto. Una página procesada no se repite.
class OcrCache {
  OcrCache._(this._file, this._pages);

  final File _file;
  final Map<int, String> _pages;

  static Future<OcrCache> open(File file) async {
    final pages = <int, String>{};
    try {
      if (await file.exists()) {
        final json = jsonDecode(await file.readAsString());
        if (json is Map && json['pages'] is Map) {
          (json['pages'] as Map).forEach((k, v) {
            final i = int.tryParse('$k');
            if (i != null) pages[i] = '$v';
          });
        }
      }
    } catch (_) {
      pages.clear();
    }
    return OcrCache._(file, pages);
  }

  bool has(int page) => _pages.containsKey(page);
  String? get(int page) => _pages[page];

  Future<void> put(int page, String text) async {
    _pages[page] = text;
    await _file.writeAsString(
      jsonEncode({'pages': _pages.map((k, v) => MapEntry('$k', v))}),
      flush: true,
    );
  }
}
