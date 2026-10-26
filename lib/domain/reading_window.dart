/// Fragmentos que se muestran en pantalla alrededor del que se está leyendo:
/// rango [inicio, fin). Cerca del principio o del final del documento se
/// desplaza para seguir mostrando la misma cantidad de texto.
(int, int) readingWindow({required int total, required int index, int before = 2, int after = 5}) {
  if (total <= 0) return (0, 0);
  final size = before + 1 + after;
  if (total <= size) return (0, total);
  var start = index - before;
  if (start < 0) start = 0;
  if (start + size > total) start = total - size;
  return (start, start + size);
}
