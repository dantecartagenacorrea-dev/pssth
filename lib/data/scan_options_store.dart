import 'package:shared_preferences/shared_preferences.dart';

import '../domain/scan_filters.dart';
import '../domain/scanned_pdf.dart';

/// Lo que se eligió la última vez para el PDF de un escaneo.
typedef ScanOptions = ({ScanPaper paper, ScanQuality quality, bool keepForm});

const ScanOptions defaultScanOptions = (paper: ScanPaper.carta, quality: ScanQuality.alta, keepForm: true);

/// Recuerda las opciones del escáner entre un escaneo y otro.
class ScanOptionsStore {
  static const _paperKey = 'scan_paper', _qualityKey = 'scan_quality', _keepFormKey = 'scan_keep_form';

  Future<ScanOptions> load() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      paper: ScanPaper.values.asNameMap()[prefs.getString(_paperKey)] ?? defaultScanOptions.paper,
      quality: ScanQuality.values.asNameMap()[prefs.getString(_qualityKey)] ?? defaultScanOptions.quality,
      keepForm: prefs.getBool(_keepFormKey) ?? defaultScanOptions.keepForm,
    );
  }

  Future<void> save(ScanOptions options) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_paperKey, options.paper.name);
    await prefs.setString(_qualityKey, options.quality.name);
    await prefs.setBool(_keepFormKey, options.keepForm);
  }
}
