/// Lo escuchado en un día: segundos con voz y palabras leídas completas.
class DayListening {
  const DayListening({this.seconds = 0, this.words = 0});

  final int seconds;
  final int words;

  DayListening plus({int seconds = 0, int words = 0}) =>
      DayListening(seconds: this.seconds + seconds, words: this.words + words);

  Map<String, dynamic> toJson() => {'s': seconds, 'w': words};

  factory DayListening.fromJson(Map<String, dynamic> j) =>
      DayListening(seconds: (j['s'] as num?)?.toInt() ?? 0, words: (j['w'] as num?)?.toInt() ?? 0);
}

/// Clave del día (2026-11-01), en la hora del aparato.
String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Un día cuenta para la racha si se escuchó al menos un minuto.
const kStreakSeconds = 60;

class ListeningSummary {
  const ListeningSummary({
    required this.today,
    required this.week,
    required this.total,
    required this.streak,
    required this.lastDays,
  });

  final DayListening today;

  /// Los últimos 7 días (hoy incluido).
  final DayListening week;
  final DayListening total;

  /// Días seguidos escuchando, contando hasta hoy (o hasta ayer, si hoy
  /// todavía no se escuchó: la racha no se corta antes de que termine el día).
  final int streak;

  /// Los últimos 7 días, del más antiguo a hoy.
  final List<(DateTime, DayListening)> lastDays;
}

ListeningSummary summarizeListening(Map<String, DayListening> days, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  DayListening at(DateTime d) => days[dayKey(d)] ?? const DayListening();
  final lastDays = [
    for (var i = 6; i >= 0; i--) (today.subtract(Duration(days: i)), at(today.subtract(Duration(days: i)))),
  ];
  var week = const DayListening();
  for (final (_, d) in lastDays) {
    week = week.plus(seconds: d.seconds, words: d.words);
  }
  var total = const DayListening();
  for (final d in days.values) {
    total = total.plus(seconds: d.seconds, words: d.words);
  }
  var streak = 0;
  var day = at(today).seconds >= kStreakSeconds ? today : today.subtract(const Duration(days: 1));
  while (at(day).seconds >= kStreakSeconds) {
    streak++;
    day = day.subtract(const Duration(days: 1));
  }
  return ListeningSummary(today: at(today), week: week, total: total, streak: streak, lastDays: lastDays);
}

/// «1 h 05 min», «12 min», «menos de 1 min».
String listeningTime(int seconds) {
  final minutes = seconds ~/ 60;
  if (minutes < 1) return seconds > 0 ? 'menos de 1 min' : '0 min';
  if (minutes < 60) return '$minutes min';
  return '${minutes ~/ 60} h ${(minutes % 60).toString().padLeft(2, '0')} min';
}
