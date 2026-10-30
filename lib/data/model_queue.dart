import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/perf_log.dart';
import 'model_store.dart';

/// Baja los modelos opcionales en segundo plano, uno detrás de otro, después
/// de preguntar una sola vez. Lo que se consulta pasa adelante.
class ModelQueue extends ChangeNotifier {
  ModelQueue(this.store, this.onInstalled) {
    store.addListener(notifyListeners);
  }

  /// La cola de la app (se crea al arrancar).
  static late ModelQueue instance;

  static const _consentKey = 'models_auto';

  final ModelStore store;

  /// Avisa al resto de la app (voz, transcripción) que hay un modelo nuevo.
  final Future<void> Function() onInstalled;

  /// null: todavía no se preguntó. true: bajar solos. false: solo a mano.
  bool? consent;
  bool _running = false;

  /// En el orden en que se bajan: primero la voz, que se usa siempre.
  static List<ModelSpec> get all => [kokoroEsModel, whisperBaseModel];

  List<ModelSpec> get missing => [
    for (final m in all)
      if (!store.isInstalled(m)) m,
  ];

  int get missingBytes => missing.fold(0, (a, m) => a + m.sizeBytes);

  /// ¿Se está bajando o instalando algo ahora?
  bool get busy => all.any(store.isInstalling);

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    consent = p.getBool(_consentKey);
  }

  Future<void> setConsent(bool value) async {
    consent = value;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_consentKey, value);
    if (value) unawaited(run());
  }

  /// Retoma lo que quedó bajando con la app cerrada y, con permiso, sigue
  /// con lo que falta.
  Future<void> start() async {
    await store.removeRetired();
    for (final m in optionalModels) {
      if (store.isInstalled(m) || store.isInstalling(m)) continue;
      if (await store.hasPendingDownload(m)) unawaited(_install(m));
    }
    if (consent == true) await run();
  }

  /// Baja lo que falta de a uno. Si algo falla (sin red), se detiene: se
  /// vuelve a intentar al abrir la app otra vez.
  Future<void> run() async {
    if (_running) return;
    _running = true;
    try {
      for (final m in all) {
        if (store.isInstalled(m)) continue;
        if (!await _install(m)) break;
      }
    } finally {
      _running = false;
    }
  }

  /// Lo que el usuario acaba de pedir baja ya, sin esperar su turno.
  void prioritize(ModelSpec m) {
    if (consent != true || store.isInstalled(m) || store.isInstalling(m)) {
      return;
    }
    unawaited(_install(m));
  }

  Future<bool> _install(ModelSpec m) async {
    try {
      await store.install(m);
      await onInstalled();
      perfLog('modelo instalado en segundo plano: ${m.id}');
      return true;
    } on ModelInstallException catch (e) {
      perfLog('no se pudo instalar ${m.id}: ${e.message}');
      return false;
    }
  }

  @override
  void dispose() {
    store.removeListener(notifyListeners);
    super.dispose();
  }
}
