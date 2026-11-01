import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../data/sync_service.dart';
import '../services/sync_controller.dart';
import 'premium.dart';

/// Ajustes > «Sincronizar con Google Drive»: la cuenta, sincronizar ahora y
/// los documentos que están en otros aparatos.
class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key, required this.sync});

  final SyncController sync;

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final _downloading = <String>{};

  SyncController get _sync => widget.sync;

  Future<void> _download(CloudDoc doc) async {
    setState(() => _downloading.add(doc.hash));
    final entry = await _sync.download(doc);
    if (!mounted) return;
    setState(() => _downloading.remove(doc.hash));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(entry == null ? 'Ya no está en tu Drive.' : '«${doc.name}» ya está en tu biblioteca.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return ListenableBuilder(
      listenable: Listenable.merge([_sync.status, _sync.cloudOnly]),
      builder: (context, _) {
        final s = _sync.status.value;
        return PremiumPage(
          title: 'Sincronizar',
          hero: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Google Drive', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(s.email ?? 'Sin cuenta', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(_statusLine(s), style: theme.textTheme.bodyMedium),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              if (!_sync.configured)
                const Text('La sincronización todavía no está configurada en esta versión de la app.')
              else if (!s.signedIn)
                FilledButton.icon(
                  onPressed: s.busy ? null : _sync.signIn,
                  icon: const Icon(CupertinoIcons.person_crop_circle),
                  label: const Text('Entrar con Google'),
                )
              else ...[
                FilledButton.icon(
                  onPressed: s.busy ? null : () => _sync.syncNow(interactive: true),
                  icon: const Icon(CupertinoIcons.arrow_2_circlepath),
                  label: const Text('Sincronizar ahora'),
                ),
                TextButton(onPressed: s.busy ? null : _sync.signOut, child: const Text('Salir de la cuenta')),
              ],
              if (s.error case final error?) ...[
                const SizedBox(height: 8),
                Text(error, style: TextStyle(color: theme.colorScheme.error)),
              ],
              if (_sync.cloudOnly.value.isNotEmpty) ...[
                const SectionCaption('En tu Drive, no en este aparato'),
                for (final doc in _sync.cloudOnly.value)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const IconAvatar(CupertinoIcons.cloud, size: 40),
                    title: Text(doc.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: _downloading.contains(doc.hash)
                        ? const CupertinoActivityIndicator()
                        : IconButton(
                            tooltip: 'Bajar a este aparato',
                            icon: const Icon(CupertinoIcons.arrow_down_circle),
                            onPressed: () => _download(doc),
                          ),
                  ),
              ],
              const SizedBox(height: 16),
              Text(
                'Se sincronizan el avance, los marcadores, las notas, la pronunciación y las estadísticas, '
                'al abrir y al salir de la app. Los documentos se suben a una carpeta oculta de tu Google Drive '
                'que solo PSSTH ve (usa tu espacio de Drive) y en cada aparato se bajan solo los que pidas. '
                'Borrar un documento lo quita solo de este aparato.',
                style: muted,
              ),
            ],
          ),
        );
      },
    );
  }

  static String _statusLine(SyncStatus s) {
    if (s.busy) return 'Sincronizando…';
    if (!s.signedIn) return 'Entra para tener tu biblioteca en todos tus aparatos.';
    final last = DateTime.tryParse(s.lastIso ?? '');
    if (last == null) return 'Todavía sin sincronizar.';
    final t = TimeOfDay.fromDateTime(last);
    return 'Sincronizado a las ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}.';
  }
}
