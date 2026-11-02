import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/retype_text.dart';

void main() {
  group('lecturas dudosas', () {
    test('se marcan', () {
      expect(looksMisread('n0 conformes'), isTrue);
      expect(looksMisread('cuando estoS se'), isTrue);
      expect(looksMisread('mi mnotoriZado'), isTrue);
    });

    test('lo normal no', () {
      expect(looksMisread('el vehículo y la placa 1234ABC'), isFalse);
      expect(looksMisread('Art. 284 del CPP'), isFalse);
      expect(looksMisread('JUAN PEREZ'), isFalse);
      expect(looksMisread('sen(30) + 2x=4'), isFalse);
      expect(looksMisread('Modelo 2021'), isFalse);
    });
  });
}
