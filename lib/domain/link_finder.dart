/// Busca una dirección web en texto leído de una foto (OCR) o de un QR.
///
/// Para no confundir "S.A." o "fin.de" con un enlace, sin "http" solo cuenta
/// lo que empieza por "www." o tiene ruta ("youtube.com/watch?v=…").
/// Si hay varios, devuelve el primero que sea de un video, o el primero.
Uri? findLinkInText(String text) {
  final found = <Uri>[];
  for (final m in _link.allMatches(text)) {
    var raw = m.group(0)!.replaceAll(RegExp(r'[.,;:!?)\]}"»”]+$'), '');
    final hasScheme = raw.toLowerCase().startsWith('http');
    final hasPath = raw.contains('/');
    if (!hasScheme && !hasPath && !raw.toLowerCase().startsWith('www.')) continue;
    if (!hasScheme) raw = 'https://$raw';
    final uri = Uri.tryParse(raw);
    if (uri == null || !uri.host.contains('.')) continue;
    found.add(uri);
  }
  if (found.isEmpty) return null;
  return found.where((u) => u.host.contains('youtu')).firstOrNull ?? found.first;
}

final _link = RegExp(
  r'(?:https?://)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:/[^\s<>"]*)?',
  caseSensitive: false,
);
