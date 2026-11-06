import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/deepseek_quota.dart';

void main() {
  test('los primeros 20 usos del día van sin aviso', () {
    expect(quotaPhase(0), QuotaPhase.normal);
    expect(quotaPhase(19), QuotaPhase.normal);
    expect(quotaNotice(19), isNull);
  });

  test('del uso 21 al 30 avisa cuántos quedan', () {
    expect(quotaPhase(20), QuotaPhase.warning);
    expect(quotaNotice(20), 'Te quedan 10 usos de DeepSeek hoy.');
    expect(quotaNotice(29), 'Te quedan 1 usos de DeepSeek hoy.');
  });

  test('después de 30 usos se pausa hasta mañana', () {
    expect(quotaPhase(30), QuotaPhase.blocked);
    expect(quotaPhase(45), QuotaPhase.blocked);
    expect(usesLeft(45), 0);
    expect(quotaNotice(30), quotaBlockedMessage);
  });

  test('al cambiar el día la cuenta vuelve a cero', () {
    final now = DateTime(2026, 11, 7, 0, 5);
    expect(usesToday(storedDay: '2026-11-06', storedUses: 30, now: now), 0);
    expect(usesToday(storedDay: '2026-11-07', storedUses: 12, now: now), 12);
    expect(usesToday(storedDay: null, storedUses: 0, now: now), 0);
    expect(dayKey(DateTime(2026, 1, 5)), '2026-01-05');
  });
}
