import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/activity.dart';
import '../core/perf_log.dart';
import 'model_store.dart';

/// Baja en segundo plano los modelos que la persona pide y retoma los que
/// quedaron a medias. Nada se baja sin que se pida: la app arranca liviana.
class ModelQueue extends ChangeNotifier {
  ModelQueue(this.store, this.onInstalled) {
    store.addListener(notifyListeners);
  }

  /// La cola de la app (se crea al arrancar).
  static late ModelQueue instance;

  final ModelStore store;

  /// Avisa a la voz que hay un modelo de voz nuevo.
  final Future<void> Function() onInstalled;

  /// ¿Se está bajando o instalando algo ahora?
  bool get busy => optionalModels.any(store.isInstalling);

  /// Retoma lo que quedó bajando con la app cerrada.
  Future<void> start() async {
    await store.removeRetired();
    for (final m in optionalModels) {
      if (store.isInstalled(m) || store.isInstalling(m)) continue;
      if (await store.hasPendingDownload(m)) unawaited(_install(m));
    }
  }

  /// Baja ya lo que la persona acaba de pedir.
  void prioritize(ModelSpec m) {
    if (store.isInstalled(m) || store.isInstalling(m)) return;
    unawaited(_install(m));
  }

  Future<bool> _install(ModelSpec m) async {
    try {
      await Activity.run('Bajando voces', () => store.install(m));
      if (isVoiceModel(m)) await onInstalled();
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
