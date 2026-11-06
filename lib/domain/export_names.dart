/// Nombres con los que salen los documentos de la biblioteca al compartirlos o
/// guardarlos: en el aparato se llaman por su número, afuera por su nombre.
List<String> exportNames(List<({String name, String storedPath})> items) {
  final used = <String>{};
  return [for (final item in items) _unique(_named(item.name, _extensionOf(item.storedPath)), used)];
}

String _extensionOf(String path) {
  final file = path.substring(path.lastIndexOf(RegExp(r'[/\\]')) + 1);
  final dot = file.lastIndexOf('.');
  return dot < 0 ? '' : file.substring(dot);
}

String _named(String name, String extension) {
  final clean = name.replaceAll(RegExp(r'[/\\:*?"<>|\x00-\x1f]'), '_').trim();
  final base = clean.isEmpty ? 'Documento' : clean;
  return base.toLowerCase().endsWith(extension.toLowerCase()) ? base : '$base$extension';
}

String _unique(String name, Set<String> used) {
  if (used.add(name.toLowerCase())) return name;
  final dot = name.lastIndexOf('.');
  final base = dot < 0 ? name : name.substring(0, dot);
  final extension = dot < 0 ? '' : name.substring(dot);
  var n = 2;
  while (!used.add('$base ($n)$extension'.toLowerCase())) {
    n++;
  }
  return '$base ($n)$extension';
}
