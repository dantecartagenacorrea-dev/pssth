// Margen diario de DeepSeek en tres fases (pedido 2026-11-06): normal, aviso y
// tope. Cuenta los resúmenes y las hojas leídas, por equipo y por día.

/// Hasta aquí, sin avisos.
const deepSeekFreeUses = 20;

/// Desde aquí se pausa hasta el día siguiente.
const deepSeekMaxUses = 30;

enum QuotaPhase { normal, warning, blocked }

/// La fase para el próximo uso, con [used] usos ya hechos hoy.
QuotaPhase quotaPhase(int used) => used >= deepSeekMaxUses
    ? QuotaPhase.blocked
    : used >= deepSeekFreeUses
    ? QuotaPhase.warning
    : QuotaPhase.normal;

int usesLeft(int used) => used >= deepSeekMaxUses ? 0 : deepSeekMaxUses - used;

/// Los usos de hoy: los guardados si son del mismo día; si no, cero.
int usesToday({required String? storedDay, required int storedUses, required DateTime now}) =>
    storedDay == dayKey(now) ? storedUses : 0;

String dayKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Qué decirle a la persona después de un uso; null si no hace falta avisar.
String? quotaNotice(int used) => switch (quotaPhase(used)) {
  QuotaPhase.normal => null,
  QuotaPhase.warning => 'Te quedan ${usesLeft(used)} usos de DeepSeek hoy.',
  QuotaPhase.blocked => quotaBlockedMessage,
};

const quotaBlockedMessage =
    'Llegaste al límite de DeepSeek de hoy ($deepSeekMaxUses usos). Mañana vuelve; mientras, se resume sin IA.';
