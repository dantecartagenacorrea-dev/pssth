import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/data/scan_options_store.dart';
import 'package:lector_pdf/domain/scan_filters.dart';
import 'package:lector_pdf/domain/scanned_pdf.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('sin nada guardado usa las opciones de siempre', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await ScanOptionsStore().load(), defaultScanOptions);
  });

  test('recuerda lo elegido', () async {
    SharedPreferences.setMockInitialValues({});
    const chosen = (paper: ScanPaper.oficio, quality: ScanQuality.liviana, keepForm: false);
    await ScanOptionsStore().save(chosen);
    expect(await ScanOptionsStore().load(), chosen);
  });

  test('un valor guardado que ya no existe vuelve al de siempre', () async {
    SharedPreferences.setMockInitialValues({'scan_paper': 'tabloide'});
    expect((await ScanOptionsStore().load()).paper, ScanPaper.carta);
  });
}
