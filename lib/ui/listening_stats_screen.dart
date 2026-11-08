import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../data/listening_store.dart';
import '../domain/listening_stats.dart';
import 'premium.dart';

/// Ajustes > «Estadísticas de escucha»: hoy, la semana, la racha y el total.
class ListeningStatsScreen extends StatelessWidget {
  const ListeningStatsScreen({super.key, required this.store});

  final ListeningStore store;

  static const _weekdays = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: store.changes,
      builder: (context, _, _) => FutureBuilder<ListeningSummary>(
        future: store.summary(),
        builder: (context, snap) {
          final s = snap.data;
          final theme = Theme.of(context);
          return PremiumPage(
            title: 'Estadísticas de escucha',
            hero: s == null
                ? null
                // Con el tema de la tarjeta (texto claro sobre fondo oscuro).
                : Builder(
                    builder: (context) {
                      final t = Theme.of(context).textTheme;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Hoy', style: t.bodyMedium),
                          Text(listeningTime(s.today.seconds), style: t.displaySmall),
                          Text('${s.today.words} palabras', style: t.bodyMedium),
                        ],
                      );
                    },
                  ),
            body: s == null
                ? const Center(child: CupertinoActivityIndicator())
                : ListView(
                    padding: const EdgeInsets.only(bottom: 24),
                    children: [
                      const SectionCaption('Últimos 7 días'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _WeekBars(days: s.lastDays, weekdays: _weekdays),
                      ),
                      const SectionCaption('Resumen'),
                      _row(context, CupertinoIcons.calendar, 'Esta semana', listeningTime(s.week.seconds)),
                      _row(
                        context,
                        CupertinoIcons.flame,
                        'Racha',
                        s.streak == 1 ? '1 día' : '${s.streak} días',
                      ),
                      _row(context, CupertinoIcons.time, 'Total', listeningTime(s.total.seconds)),
                      _row(context, CupertinoIcons.text_alignleft, 'Palabras escuchadas', '${s.total.words}'),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                        child: Text(
                          'Cuenta el tiempo con la voz sonando. La racha suma los días con al menos un minuto. '
                          'Si sincronizas con Google Drive, suma lo de tus otros aparatos.',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, IconData icon, String label, String value) => ListTile(
    leading: IconAvatar(icon, size: 40),
    title: Text(label),
    trailing: Text(value, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// Barras de los últimos días: alto según los minutos, hoy resaltado.
class _WeekBars extends StatelessWidget {
  const _WeekBars({required this.days, required this.weekdays});

  final List<(DateTime, DayListening)> days;
  final List<String> weekdays;

  static const _barHeight = 120.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final most = days.fold<int>(0, (m, d) => d.$2.seconds > m ? d.$2.seconds : m);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < days.length; i++)
          Expanded(
            child: Semantics(
              label: '${weekdays[days[i].$1.weekday - 1]}: ${listeningTime(days[i].$2.seconds)}',
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    height: most == 0 ? 4 : 4 + (_barHeight - 4) * days[i].$2.seconds / most,
                    decoration: BoxDecoration(
                      color: i == days.length - 1 ? scheme.primary : scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(weekdays[days[i].$1.weekday - 1], style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
