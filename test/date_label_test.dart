import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/date_label.dart';

void main() {
  final now = DateTime(2026, 10, 30, 9);

  test('hoy, ayer y fechas del año con el mes en palabras', () {
    expect(dayLabel(DateTime(2026, 10, 30, 0, 5), now), 'Hoy');
    expect(dayLabel(DateTime(2026, 10, 29, 23, 59), now), 'Ayer');
    expect(dayLabel(DateTime(2026, 10, 27), now), '27 de octubre');
    expect(dayLabel(DateTime(2026, 1, 3), now), '3 de enero');
  });

  test('otro año lleva el año y sin fecha es «Antes»', () {
    expect(dayLabel(DateTime(2025, 12, 31), now), '31 de diciembre de 2025');
    expect(dayLabel(null, now), 'Antes');
  });
}
