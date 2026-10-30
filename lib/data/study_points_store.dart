import 'package:shared_preferences/shared_preferences.dart';

/// Puntos de las preguntas de estudio: los de cada documento, el total y la
/// mejor racha. Se guardan en el equipo.
typedef StudyPoints = ({int document, int total, int bestStreak});

class StudyPointsStore {
  static const _totalKey = 'estudio_puntos_total';
  static String _docKey(String id) => 'estudio_puntos_$id';
  static String _streakKey(String id) => 'estudio_racha_$id';

  Future<StudyPoints> load(String documentId) async {
    final p = await SharedPreferences.getInstance();
    return (
      document: p.getInt(_docKey(documentId)) ?? 0,
      total: p.getInt(_totalKey) ?? 0,
      bestStreak: p.getInt(_streakKey(documentId)) ?? 0,
    );
  }

  /// Suma [points] al documento y al total, y guarda la racha si es la mejor.
  Future<StudyPoints> add(String documentId, int points, {required int streak}) {
    // De a una: dos respuestas seguidas leían el mismo total y se perdía una suma.
    final next = _adding.then((_) => _add(documentId, points, streak: streak));
    _adding = next.then((_) {}, onError: (_) {});
    return next;
  }

  static Future<void> _adding = Future.value();

  Future<StudyPoints> _add(String documentId, int points, {required int streak}) async {
    final p = await SharedPreferences.getInstance();
    final now = await load(documentId);
    final next = (
      document: now.document + points,
      total: now.total + points,
      bestStreak: streak > now.bestStreak ? streak : now.bestStreak,
    );
    await p.setInt(_docKey(documentId), next.document);
    await p.setInt(_totalKey, next.total);
    await p.setInt(_streakKey(documentId), next.bestStreak);
    return next;
  }
}
