import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/activity.dart';
import '../core/perf_log.dart';
import '../data/library_store.dart';
import '../data/sync_service.dart';
import '../domain/library_entry.dart';
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

/// Sincroniza con el Google Drive de la persona: al abrir la app (si ya había
/// entrado), al salir de ella y cuando lo pide. También sube los documentos
/// que falten y baja, cuando se piden, los que solo están en otros aparatos.
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

  bool get configured => _drive.configured;

  Future<void>? _running;

  /// Al abrir la app: entra sin preguntar si ya había entrado y sincroniza.
  Future<void> start() async {
    try {
      final account = await _drive.signInSilently();
      if (account == null) return;
      status.value = SyncStatus(email: account.email);
      await syncNow();
    } on Exception catch (e) {
      perfLog('sincronizar: no se pudo entrar: $e');
    }
  }

  Future<void> signIn() async {
    status.value = SyncStatus(email: status.value.email, busy: true);
    try {
      final account = await _drive.signIn();
      status.value = SyncStatus(email: account.email);
      await syncNow(interactive: true);
    } on Exception catch (e) {
      status.value = SyncStatus(error: _message(e));
    }
  }

  Future<void> signOut() async {
    await _drive.signOut();
    cloudOnly.value = const [];
    status.value = const SyncStatus();
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
        status.value = SyncStatus(email: email, error: 'Falta el permiso para tu Drive: toca «Sincronizar ahora».');
        return;
      }
      final merged = await service.syncWith(remote);
      changes.value++;
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

  /// Baja un documento que está en otro aparato y lo suma a la biblioteca
  /// con su avance. null si ya no está en el Drive.
  Future<LibraryEntry?> download(CloudDoc doc) async {
    final bytes = await Activity.run('Bajando documento', () => _drive.downloadDoc(doc.hash));
    if (bytes == null) return null;
    final entry = await library.importFile(originalName: doc.name, bytes: bytes);
    await syncNow(); // trae su avance, marcadores y notas
    return library.byId(entry.id);
  }

  static String _message(Exception e) {
    final text = '$e';
    if (text.contains('canceled') || text.contains('cancelled')) return 'Se canceló la entrada a Google.';
    if (e is SocketException || text.contains('SocketException')) return 'Sin conexión: se sincroniza la próxima vez.';
    return 'No se pudo sincronizar. Se vuelve a intentar al abrir la app.';
  }
}
