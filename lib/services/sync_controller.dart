import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/activity.dart';
import '../core/perf_log.dart';
import '../data/library_store.dart';
import '../data/sync_service.dart';
import '../platform/drive_sync.dart';

/// Cómo va la sincronización, para la pantalla.
class SyncStatus {
  const SyncStatus({this.email, this.busy = false, this.lastIso, this.error});
  final String? email;
  final bool busy;
  final String? lastIso;
  final String? error;

  bool get signedIn => email != null;
}

/// Sincroniza con el Google Drive de la persona, sola y en segundo plano: al
/// abrir la app (si ya autorizó) y al salir de ella. Sube los documentos que
/// falten y baja los que están en otros aparatos, salvo los que se borraron
/// aquí. A la persona solo se le pide autorizar.
class SyncController {
  SyncController({required this.service, required this.library, DriveSync? drive})
    : _drive = drive ?? DriveSync.instance;

  static SyncController? instance;

  final SyncService service;
  final LibraryStore library;
  final DriveSync _drive;

  final status = ValueNotifier(const SyncStatus());

  /// En el Drive (de otros aparatos) pero no en este.
  final cloudOnly = ValueNotifier<List<CloudDoc>>(const []);

  /// Cambia cuando la sincronización cambió la biblioteca (avance, marcas).
  final changes = ValueNotifier(0);

  /// Había autorizado y Google pide hacerlo de nuevo (permiso vencido o
  /// quitado): la pantalla ofrece «Autorizar» una vez.
  final needsAuthorization = ValueNotifier(false);

  bool get configured => _drive.configured;

  static const _askedKey = 'sync_asked';
  static const _onKey = 'sync_on';
  static const _skipKey = 'sync_skip';

  Future<void>? _running;

  /// La entrada sin preguntar del arranque: hasta que termine no se sabe si
  /// ya había autorizado.
  final _signedInChecked = Completer<void>();

  /// Al abrir la app: entra sin preguntar si ya había autorizado y sincroniza.
  Future<void> start() async {
    try {
      final account = await _drive.signInSilently();
      final prefs = await SharedPreferences.getInstance();
      if (account == null) {
        if (prefs.getBool(_onKey) ?? false) needsAuthorization.value = true;
        return;
      }
      await prefs.setBool(_onKey, true);
      status.value = SyncStatus(email: account.email);
      if (!_signedInChecked.isCompleted) _signedInChecked.complete();
      await syncNow();
    } on Exception catch (e) {
      perfLog('sincronizar: no se pudo entrar: $e');
    } finally {
      if (!_signedInChecked.isCompleted) _signedInChecked.complete();
    }
  }

  /// Si conviene preguntar una sola vez si quiere tener su biblioteca en Drive.
  /// Espera la entrada sin preguntar del arranque (como mucho unos segundos).
  Future<bool> shouldOffer() async {
    if (!configured) return false;
    await _signedInChecked.future.timeout(const Duration(seconds: 10), onTimeout: () {});
    if (status.value.signedIn) return false;
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool(_askedKey) ?? false);
  }

  Future<void> markOffered() async => (await SharedPreferences.getInstance()).setBool(_askedKey, true);

  /// Autorizar con Google (siempre desde un botón: Android lo exige). Después
  /// todo sigue solo.
  Future<void> signIn() async {
    status.value = SyncStatus(email: status.value.email, busy: true);
    try {
      final account = await _drive.signIn();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_onKey, true);
      await prefs.setBool(_askedKey, true);
      needsAuthorization.value = false;
      status.value = SyncStatus(email: account.email);
      await syncNow(interactive: true);
    } on Exception catch (e) {
      status.value = SyncStatus(error: _message(e));
    }
  }

  Future<void> signOut() async {
    await _drive.signOut();
    await (await SharedPreferences.getInstance()).setBool(_onKey, false);
    needsAuthorization.value = false;
    cloudOnly.value = const [];
    status.value = const SyncStatus();
  }

  /// Se borró aquí: no volver a bajarlo de otro aparato.
  Future<void> keepOff(String? hash) async {
    if (hash == null) return;
    final prefs = await SharedPreferences.getInstance();
    final skip = prefs.getStringList(_skipKey) ?? const [];
    if (!skip.contains(hash)) await prefs.setStringList(_skipKey, [...skip, hash]);
  }

  /// Sincroniza ahora (si ya hay una en curso, espera esa).
  Future<void> syncNow({bool interactive = false}) =>
      _running ??= Activity.run('Sincronizando', () => _sync(interactive)).whenComplete(() => _running = null);

  Future<void> _sync(bool interactive) async {
    final email = status.value.email;
    if (email == null) return;
    status.value = SyncStatus(email: email, busy: true, lastIso: status.value.lastIso);
    try {
      final remote = await _drive.stateFile(interactive: interactive);
      if (remote == null) {
        needsAuthorization.value = true;
        status.value = SyncStatus(email: email, error: 'Google pide volver a autorizar el acceso a tu Drive.');
        return;
      }
      var merged = await service.syncWith(remote);
      changes.value++;
      if (await _downloadMissing(service.cloudOnly(merged))) {
        merged = await service.syncWith(remote); // trae su avance, marcadores y notas
        changes.value++;
      }
      cloudOnly.value = service.cloudOnly(merged);
      await _uploadMissing();
      status.value = SyncStatus(email: email, lastIso: DateTime.now().toIso8601String());
    } on Exception catch (e) {
      perfLog('sincronizar: $e');
      status.value = SyncStatus(email: email, lastIso: status.value.lastIso, error: _message(e));
    }
  }

  /// Sube a su Drive los documentos de este aparato que todavía no están.
  Future<void> _uploadMissing() async {
    final there = await _drive.uploadedDocs();
    for (final e in List.of(library.data.entries)) {
      final hash = e.contentHash;
      if (hash == null || there.contains(hash)) continue;
      final file = File(e.storedPath);
      if (!await file.exists()) continue;
      await _drive.uploadDoc(hash, file);
      perfLog('sincronizar: subido ${e.name}');
    }
  }

  /// Baja los documentos de otros aparatos que no se borraron aquí. true si
  /// bajó alguno. Uno que falla se reintenta la próxima vez.
  Future<bool> _downloadMissing(List<CloudDoc> docs) async {
    final skip = (await SharedPreferences.getInstance()).getStringList(_skipKey)?.toSet() ?? const {};
    var any = false;
    for (final doc in docs) {
      if (skip.contains(doc.hash)) continue;
      try {
        final bytes = await Activity.run('Bajando documento', () => _drive.downloadDoc(doc.hash));
        if (bytes == null) continue;
        await library.importFile(originalName: doc.name, bytes: bytes);
        any = true;
        perfLog('sincronizar: bajado ${doc.name}');
      } on Exception catch (e) {
        perfLog('sincronizar: no se pudo bajar ${doc.name}: $e');
      }
    }
    return any;
  }

  static String _message(Exception e) {
    final text = '$e';
    if (text.contains('canceled') || text.contains('cancelled')) return 'Se canceló la entrada a Google.';
    if (e is SocketException || text.contains('SocketException')) return 'Sin conexión: se sincroniza la próxima vez.';
    return 'No se pudo sincronizar. Se vuelve a intentar al abrir la app.';
  }
}
