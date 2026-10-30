import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/services/transcript_cleaner.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preparar la limpieza una vez da el mismo texto que limpiar trozo a trozo', () async {
    SharedPreferences.setMockInitialValues({});
    final c = TranscriptCleaner.instance;
    const doc = 'El asiento contable del balance y el libro diario. La cuenta de activo y pasivo del ejercicio.';
    final pages = ['El asiento contable del balance', 'y el libro diario.', 'La cuenta de activo y pasivo del ejercicio.'];
    final clean = c.cleanerFor(doc);
    for (final p in pages) {
      expect(clean(p), c.clean(p, context: doc));
    }
  });
}
