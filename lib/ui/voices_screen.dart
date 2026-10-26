import 'dart:io';

import 'package:flutter/material.dart';

import '../data/model_store.dart';
import '../platform/native_text.dart';

/// Voces y modelos opcionales. Todo se descarga una vez y funciona sin conexión.
class VoicesScreen extends StatefulWidget {
  const VoicesScreen({
    super.key,
    required this.modelStore,
    required this.onModelsChanged,
    required this.native,
  });

  final ModelStore modelStore;

  /// Se llama tras instalar o eliminar un modelo (para recargar voces, etc.).
  final Future<void> Function() onModelsChanged;
  final NativeText native;

  @override
  State<VoicesScreen> createState() => _VoicesScreenState();
}

class _VoicesScreenState extends State<VoicesScreen> {
  final Map<String, ModelProgress?> _progress = {};
  final Map<String, String?> _errors = {};
  final Map<String, int> _sizes = {};
  String? _personalVoiceMsg;

  @override
  void initState() {
    super.initState();
    _refreshSizes();
  }

  Future<void> _refreshSizes() async {
    for (final m in [kokoroEsModel, whisperBaseModel]) {
      _sizes[m.id] = await widget.modelStore.installedBytes(m);
    }
    if (mounted) setState(() {});
  }

  Future<void> _install(ModelSpec m) async {
    setState(() {
      _errors[m.id] = null;
      _progress[m.id] = const ModelProgress(ModelPhase.downloading, 0);
    });
    try {
      await widget.modelStore.install(m, onProgress: (p) {
        if (mounted) setState(() => _progress[m.id] = p);
      });
      await widget.onModelsChanged();
    } on ModelInstallException catch (e) {
      _errors[m.id] = e.message;
    } catch (e) {
      _errors[m.id] = 'No se pudo instalar.';
    } finally {
      _progress[m.id] = null;
      await _refreshSizes();
    }
  }

  Future<void> _remove(ModelSpec m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Eliminar "${m.title}"?'),
        content: const Text('Se borra del dispositivo. Podrás volver a instalarlo cuando quieras.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.modelStore.remove(m);
    await widget.onModelsChanged();
    await _refreshSizes();
  }

  Future<void> _personalVoice() async {
    final ok = await widget.native.requestPersonalVoice();
    await widget.onModelsChanged();
    setState(() {
      _personalVoiceMsg = ok
          ? 'Tu voz personal ya aparece en el selector de voz.'
          : 'No hay voz personal autorizada. Créala en Ajustes → Accesibilidad → Voz personal y vuelve a intentarlo.';
    });
  }

  Widget _modelTile(ModelSpec m, String description) {
    final installed = widget.modelStore.isInstalled(m);
    final p = _progress[m.id];
    final err = _errors[m.id];
    final size = _sizes[m.id] ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(m.title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(description, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 12),
            if (p != null) ...[
              LinearProgressIndicator(value: p.fraction),
              const SizedBox(height: 6),
              Text(p.label, style: Theme.of(context).textTheme.bodySmall),
            ] else if (installed)
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Instalado · ${(size / (1024 * 1024)).round()} MB en el dispositivo')),
                  TextButton(onPressed: () => _remove(m), child: const Text('Eliminar')),
                ],
              )
            else
              FilledButton.icon(
                onPressed: () => _install(m),
                icon: const Icon(Icons.download),
                label: Text('Instalar (${m.sizeLabel}, una sola vez)'),
              ),
            if (err != null) ...[
              const SizedBox(height: 8),
              Text(err, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voces y modelos')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.phone_iphone),
              title: Text(Platform.isIOS ? 'Voz del iPhone' : 'Voz del sistema'),
              subtitle: Text(
                Platform.isIOS
                    ? 'Rápida y ligera. Para mejor calidad, descarga una voz "Mejorada" o "Premium" en Ajustes → Accesibilidad → Contenido hablado → Voces.'
                    : 'Rápida y ligera. Puedes instalar más voces en los ajustes de texto a voz del sistema.',
              ),
            ),
          ),
          const SizedBox(height: 8),
          _modelTile(
            kokoroEsModel,
            'Mayor naturalidad en español (voces Dora y Alex). Funciona sin conexión después de instalarse. '
            'Necesita un teléfono reciente; si va lento, PSSTH! vuelve solo a la voz del sistema.',
          ),
          if (Platform.isIOS) ...[
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mi voz personal', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    const Text(
                      'Si creaste tu Voz personal en iOS (Ajustes → Accesibilidad → Voz personal), '
                      'PSSTH! puede leer con ella. Solo tu propia voz, con tu permiso; nada sale del iPhone.',
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonal(onPressed: _personalVoice, child: const Text('Usar mi voz personal')),
                    if (_personalVoiceMsg != null) ...[
                      const SizedBox(height: 8),
                      Text(_personalVoiceMsg!, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          _modelTile(
            whisperBaseModel,
            Platform.isIOS
                ? 'Para grabaciones en idiomas que el iPhone no transcribe sin conexión. Normalmente no hace falta.'
                : 'Convierte en texto las clases o conversaciones grabadas, sin Internet y sin salir del dispositivo.',
          ),
          const SizedBox(height: 16),
          Text(
            'Los modelos vienen del proyecto sherpa-onnx (licencia Apache 2.0) y se verifican antes de instalarse. '
            'Ningún documento ni grabación sale del dispositivo.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
