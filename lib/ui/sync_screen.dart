import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/sync_controller.dart';
import 'premium.dart';

/// Ajustes > «Sincronizar con Google Drive»: autorizar una vez y ver cómo va.
/// Lo demás (subir, bajar, mezclar) se hace solo, en segundo plano.
class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key, required this.sync});

  final SyncController sync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return ListenableBuilder(
      listenable: Listenable.merge([sync.status, sync.needsAuthorization]),
      builder: (context, _) {
        final s = sync.status.value;
        final authorize = !s.signedIn || sync.needsAuthorization.value;
        return PremiumPage(
          title: 'Sincronizar',
          // Con el tema de la tarjeta (texto claro sobre fondo oscuro).
          hero: Builder(
            builder: (context) {
              final t = Theme.of(context).textTheme;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Google Drive', style: t.bodyMedium),
                  const SizedBox(height: 4),
                  Text(s.email ?? 'Sin conectar', style: t.titleLarge),
                  const SizedBox(height: 4),
                  Text(statusLine(s), style: t.bodyMedium),
                ],
              );
            },
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              if (!sync.configured)
                const Text('La sincronización todavía no está configurada en esta versión de la app.')
              else if (authorize)
                FilledButton.icon(
                  onPressed: s.busy ? null : sync.signIn,
                  icon: const Icon(CupertinoIcons.person_crop_circle),
                  label: const Text('Autorizar con Google'),
                )
              else
                TextButton(onPressed: s.busy ? null : sync.signOut, child: const Text('Desconectar')),
              if (s.error case final error?) ...[
                const SizedBox(height: 8),
                Text(error, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 16),
              Text(
                'Se hace solo, al abrir y al salir de la app: tu avance, marcadores, notas, pronunciación, '
                'estadísticas y documentos quedan en una carpeta oculta de tu Google Drive que solo PSSTH ve '
                '(usa tu espacio de Drive). En tus otros aparatos aparecen solos. Borrar un documento lo quita '
                'solo de este aparato.',
                style: muted,
              ),
            ],
          ),
        );
      },
    );
  }

  static String statusLine(SyncStatus s) {
    if (s.busy) return 'Sincronizando…';
    if (!s.signedIn) return 'Conéctalo para tener tu biblioteca en todos tus aparatos.';
    final last = DateTime.tryParse(s.lastIso ?? '');
    if (last == null) return 'Conectado.';
    final t = TimeOfDay.fromDateTime(last);
    return 'Al día desde las ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}.';
  }
}
