/// Texto legible de una página web: título y párrafos, sin menús, scripts ni
/// anuncios. Sin dependencias: expresiones regulares sobre el HTML, suficiente
/// para artículos, noticias y blogs. Las páginas que arman el texto con
/// JavaScript devuelven poco o nada (no se ejecuta código de la página).
class HtmlText {
  const HtmlText({required this.title, required this.text});

  final String title;
  final String text;

  int get wordCount => RegExp(r'\p{L}+', unicode: true).allMatches(text).length;
}

/// Mínimo de palabras para que <article>/<main> se prefiera al cuerpo entero.
const _minMainWords = 80;

HtmlText extractHtmlText(String html) {
  final title = _clean(_firstGroup(html, r'<meta[^>]+property="og:title"[^>]+content="([^"]*)"') ??
      _firstGroup(html, r'<title[^>]*>(.*?)</title>') ??
      '');

  var body = html.replaceAll(
    RegExp(
      r'<(head|title|script|style|noscript|svg|template|iframe|nav|header|footer|aside|form|button|select)\b[^>]*>.*?</\1\s*>',
      caseSensitive: false,
      dotAll: true,
    ),
    ' ',
  );
  body = body.replaceAll(RegExp(r'<!--.*?-->', dotAll: true), ' ');

  // Si hay un bloque principal con contenido suficiente, quedarse con él.
  for (final tag in const ['article', 'main']) {
    final inner = _allGroups(body, '<$tag\\b[^>]*>(.*?)</$tag\\s*>');
    if (inner.isEmpty) continue;
    final joined = inner.join('\n');
    if (_toText(joined).split(RegExp(r'\s+')).length >= _minMainWords) {
      body = joined;
      break;
    }
  }

  return HtmlText(title: title, text: _toText(body));
}

String _toText(String html) {
  var t = html.replaceAll(
    RegExp(r'<(br|/p|/div|/h[1-6]|/li|/tr|/blockquote|/section|/article|/pre)\b[^>]*>', caseSensitive: false),
    '\n',
  );
  t = t.replaceAll(RegExp(r'<li\b[^>]*>', caseSensitive: false), '\n');
  // Las etiquetas de línea (enlaces, negritas) no separan palabras.
  t = t.replaceAll(RegExp(r'</?(a|b|i|em|strong|span|small|sup|sub|mark|abbr|code)\b[^>]*>', caseSensitive: false), '');
  t = t.replaceAll(RegExp(r'<[^>]+>'), ' ');
  t = decodeHtmlEntities(t);
  final lines = <String>[];
  for (final raw in t.split('\n')) {
    final line = raw.replaceAll(RegExp(r'[ \t ]+'), ' ').trim();
    if (line.isEmpty) continue;
    lines.add(line);
  }
  return lines.join('\n\n');
}

String _clean(String s) => decodeHtmlEntities(s.replaceAll(RegExp(r'<[^>]+>'), ' '))
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

String? _firstGroup(String s, String pattern) =>
    RegExp(pattern, caseSensitive: false, dotAll: true).firstMatch(s)?.group(1);

List<String> _allGroups(String s, String pattern) => [
      for (final m in RegExp(pattern, caseSensitive: false, dotAll: true).allMatches(s)) m.group(1)!,
    ];

const _named = {
  'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ',
  'aacute': 'á', 'eacute': 'é', 'iacute': 'í', 'oacute': 'ó', 'uacute': 'ú',
  'Aacute': 'Á', 'Eacute': 'É', 'Iacute': 'Í', 'Oacute': 'Ó', 'Uacute': 'Ú',
  'ntilde': 'ñ', 'Ntilde': 'Ñ', 'uuml': 'ü', 'Uuml': 'Ü', 'ccedil': 'ç',
  'iexcl': '¡', 'iquest': '¿', 'laquo': '«', 'raquo': '»', 'ordm': 'º', 'ordf': 'ª',
  'hellip': '…', 'mdash': '—', 'ndash': '–', 'lsquo': '‘', 'rsquo': '’',
  'ldquo': '“', 'rdquo': '”', 'bull': '•', 'middot': '·', 'deg': '°', 'euro': '€',
};

String decodeHtmlEntities(String s) => s.replaceAllMapped(
      RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);'),
      (m) {
        final code = m[1]!;
        if (code.startsWith('#')) {
          final n = code.startsWith('#x') || code.startsWith('#X')
              ? int.tryParse(code.substring(2), radix: 16)
              : int.tryParse(code.substring(1));
          if (n == null || n <= 0 || n > 0x10FFFF) return m[0]!;
          return n == 0xA0 ? ' ' : String.fromCharCode(n);
        }
        return _named[code] ?? m[0]!;
      },
    );
