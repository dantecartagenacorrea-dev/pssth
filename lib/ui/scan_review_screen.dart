import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../domain/scan_filters.dart';
import 'fragment_image.dart';

/// Página limpia lista para el PDF.
typedef CleanPage = ({Uint8List jpeg, int width, int height});

/// Revisión de lo escaneado: se elige cómo limpiar las páginas (B&N, Mejorar,
/// grises u original) viendo cómo queda, y se confirma. Devuelve las páginas
/// limpias, en orden, o null si se cancela.
class ScanReviewScreen extends StatefulWidget {
  const ScanReviewScreen({super.key, required this.paths});

  final List<String> paths;

  @override
  State<ScanReviewScreen> createState() => _ScanReviewScreenState();
}

class _ScanReviewScreenState extends State<ScanReviewScreen> {
  ScanFilter _filter = ScanFilter.byn;
  int _page = 0;
  bool _finishing = false;

  /// Páginas ya limpias, por filtro: cambiar de filtro y volver es instantáneo.
  final _done = <(ScanFilter, int), Future<CleanPage>>{};
  final _originals = <int, Future<Uint8List>>{};

  Future<CleanPage> _clean(int page, ScanFilter filter) => _done.putIfAbsent((filter, page), () async {
        final jpeg = await _originals.putIfAbsent(page, () => File(widget.paths[page]).readAsBytes());
        return applyScanFilter(jpeg, filter);
      });

  Future<void> _finish() async {
    setState(() => _finishing = true);
    try {
      final pages = [for (var i = 0; i < widget.paths.length; i++) await _clean(i, _filter)];
      if (mounted) Navigator.pop(context, pages);
    } catch (error) {
      if (!mounted) return;
      setState(() => _finishing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo preparar la página: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.paths.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(total == 1 ? 'Revisar escaneo' : 'Revisar escaneo · ${_page + 1} de $total'),
        actions: [
          TextButton(
            onPressed: _finishing ? null : _finish,
            child: _finishing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Listo'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              itemCount: total,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.all(16),
                child: FutureBuilder<CleanPage>(
                  future: _clean(i, _filter),
                  builder: (context, snap) {
                    final page = snap.data;
                    if (page == null) {
                      return snap.hasError
                          ? Center(child: Text('No se pudo mostrar la página: ${snap.error}'))
                          : const SizedBox.expand();
                    }
                    // La hoja se arma desde la dispersión, como las letras.
                    return InteractiveViewer(maxScale: 5, child: FragmentImage(jpeg: page.jpeg));
                  },
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in ScanFilter.values)
                    ChoiceChip(
                      label: Text(f.label),
                      selected: _filter == f,
                      onSelected: _finishing ? null : (_) => setState(() => _filter = f),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
