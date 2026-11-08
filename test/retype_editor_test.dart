import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/scanned_pdf.dart';
import 'package:lector_pdf/ui/retype_editor.dart';

/// PNG de 1×1 para la foto (no importa qué muestra).
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xFF, 0xFF, 0x3F,
  0x00, 0x05, 0xFE, 0x02, 0xFE, 0xA7, 0x35, 0x81, 0x84, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
  0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void main() {
  testWidgets('corregir un renglón dudoso baja el contador', (tester) async {
    const lines = <ScannedLine>[
      (text: 'Contrato de alquiler', left: 0, top: 0, width: 100, height: 10),
      (text: 'Monto: 1500 Bs', left: 0, top: 20, width: 100, height: 10),
    ];
    final controllers = [for (final l in lines) TextEditingController(text: l.text)];
    addTearDown(() {
      for (final c in controllers) {
        c.dispose();
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RetypeEditor(
            photo: MemoryImage(_png),
            width: 100,
            height: 40,
            lines: lines,
            controllers: controllers,
            doubts: const {0, 1},
          ),
        ),
      ),
    );
    expect(find.textContaining('Hay 2 renglones dudosos'), findsOneWidget);

    controllers[1].text = 'Monto: 1.500 Bs';
    await tester.pump();
    expect(find.textContaining('Hay 1 renglón dudoso'), findsOneWidget);

    controllers[0].text = 'Contrato de alquiler.';
    await tester.pump();
    expect(find.textContaining('dudoso'), findsNothing);
  });
}
