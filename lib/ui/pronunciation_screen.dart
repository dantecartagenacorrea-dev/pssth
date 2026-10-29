import 'package:flutter/material.dart';

import '../data/pronunciation_store.dart';
import 'swarm_transition.dart';

class PronunciationScreen extends StatefulWidget {
  const PronunciationScreen({super.key, required this.store});
  final PronunciationStore store;

  @override
  State<PronunciationScreen> createState() => _PronunciationScreenState();
}

class _PronunciationScreenState extends State<PronunciationScreen> {
  Map<String, String> _entries = {};

  @override
  void initState() {
    super.initState();
    widget.store.load().then((e) {
      if (mounted) setState(() => _entries = Map.of(e));
    });
  }

  Future<void> _add() async {
    final written = TextEditingController();
    final spoken = TextEditingController();
    final ok = await showSwarmDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nueva pronunciación'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: written,
              decoration: const InputDecoration(labelText: 'Texto escrito (p. ej. SIN)'),
            ),
            TextField(
              controller: spoken,
              decoration: const InputDecoration(labelText: 'Se lee como'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.set(written.text, spoken.text);
    if (mounted) setState(() => _entries = Map.of(widget.store.entries));
  }

  @override
  Widget build(BuildContext context) {
    final keys = _entries.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('Pronunciación')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Agregar',
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: keys.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aquí puedes indicar cómo se pronuncian siglas, nombres o términos. Se aplica al abrir un documento.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: [
                for (final k in keys)
                  ListTile(
                    title: Text(k),
                    subtitle: Text(_entries[k]!),
                    trailing: IconButton(
                      tooltip: 'Eliminar',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await widget.store.remove(k);
                        if (mounted) setState(() => _entries = Map.of(widget.store.entries));
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}
