import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/library_entry.dart';

void main() {
  test('serializa y restaura la biblioteca', () {
    final original = LibraryData(
      entries: [
        LibraryEntry(
          id: '1',
          name: 'libro.pdf',
          storedPath: '/tmp/1.pdf',
          pageCount: 10,
          totalChunks: 40,
          pageIndex: 3,
          chunkIndex: 1,
          lastOpenedIso: '2026-09-18T12:00:00.000',
        ),
      ],
    );

    final restored = LibraryData.fromJson(original.toJson());
    expect(restored.entries, hasLength(1));
    final entry = restored.entries.first;
    expect(entry.id, '1');
    expect(entry.name, 'libro.pdf');
    expect(entry.pageIndex, 3);
    expect(entry.chunkIndex, 1);
    expect(entry.pageCount, 10);
    expect(entry.progress, closeTo(0.3, 0.001)); // inicio de la página 4 de 10
  });

  test('JSON inválido produce biblioteca vacía', () {
    final restored = LibraryData.fromJson({'entries': 'no'});
    expect(restored.entries, isEmpty);
  });
}
