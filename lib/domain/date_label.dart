const _months = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

/// Rótulo del día para agrupar listas: «Hoy», «Ayer», «27 de octubre» (con el
/// año si no es el actual). Sin fecha: «Antes».
String dayLabel(DateTime? when, DateTime now) {
  if (when == null) return 'Antes';
  final day = DateTime(when.year, when.month, when.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Ayer';
  final base = '${when.day} de ${_months[when.month - 1]}';
  return when.year == now.year ? base : '$base de ${when.year}';
}
