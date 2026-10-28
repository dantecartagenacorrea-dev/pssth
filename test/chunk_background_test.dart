import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/chunk_builder.dart';
import 'package:lector_pdf/domain/text_normalizer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('en segundo plano da lo mismo', () async {
    SharedPreferences.setMockInitialValues({});
    final pages = ['El asiento contable del balance. Uno dos tres.', 'La cuenta de activo y pasivo del ejercicio.'];
    final a = buildChunks(documentId: 'd', pages: pages, normalizer: TextNormalizer());
    final b = await buildChunksInBackground(documentId: 'd', pages: pages, normalizer: TextNormalizer());
    expect(b.map((c) => (c.text, c.speech, c.pageIndex)).toList(), a.map((c) => (c.text, c.speech, c.pageIndex)).toList());
  });
}
