import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/scanned_pdf.dart';

/// JPEG mínimo válido de 1×1 píxel.
final _jpeg = base64Decode(
  '/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=',
);

void main() {
  test('el PDF lleva la foto y el texto reconocido, buscable', () async {
    final pages = <ScannedPage>[
      (
        jpeg: Uint8List.fromList(_jpeg),
        width: 1000,
        height: 1400,
        lines: [
          (text: 'Factura número 123', left: 0.1, top: 0.1, width: 0.5, height: 0.03),
          (text: 'Total: 450 Bs.', left: 0.1, top: 0.2, width: 0.3, height: 0.03),
        ],
      ),
      (jpeg: Uint8List.fromList(_jpeg), width: 1000, height: 1400, lines: const []),
    ];
    final bytes = await buildScannedPdf(pages, title: 'Prueba', compress: false);
    final raw = latin1.decode(bytes);
    expect(raw, startsWith('%PDF'));
    expect(RegExp(r'/Type\s*/Page\b').allMatches(raw).length, 2);
    expect(raw, contains('3 Tr'), reason: 'modo de texto invisible');
    expect(raw, matches(RegExp(r'/Subtype\s*/Image')));
  });

  test('cambia los caracteres que la letra del PDF no tiene', () {
    expect(latin1Safe('«Año» — “ñandú” …'), '«Año» - "ñandú" ...');
    expect(latin1Safe('Ω'), '?');
  });

  test('nombre sugerido con fecha y hora, y nombre de archivo limpio', () {
    final now = DateTime(2026, 10, 28, 0, 45);
    expect(defaultScanName(now), 'Escaneo 2026-10-28 00-45');
    expect(safePdfFileName('Contrato: KAR/2026', now), 'Contrato_ KAR_2026.pdf');
    expect(safePdfFileName('  recibo.PDF ', now), 'recibo.pdf');
    expect(safePdfFileName('   ', now), 'Escaneo 2026-10-28 00-45.pdf');
  });
}
