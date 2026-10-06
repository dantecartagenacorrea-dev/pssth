import 'package:flutter_test/flutter_test.dart';
import 'package:lector_pdf/domain/reading_position.dart';

void main() {
  const chunks = [
    (pageIndex: 0, chunkIndex: 0),
    (pageIndex: 0, chunkIndex: 1),
    (pageIndex: 1, chunkIndex: 0),
    (pageIndex: 2, chunkIndex: 0),
  ];

  test('resuelve coincidencia exacta', () {
    const position = ReadingPosition(pageIndex: 1, chunkIndex: 0);
    expect(position.resolveChunkListIndex(chunks), 2);
  });

  test('si el chunk no existe usa la página', () {
    const position = ReadingPosition(pageIndex: 0, chunkIndex: 9);
    expect(position.resolveChunkListIndex(chunks), 0);
  });

  test('si la página no tiene texto usa la siguiente disponible', () {
    const position = ReadingPosition(pageIndex: 1, chunkIndex: 5);
    expect(position.resolveChunkListIndex(chunks), 2);
  });

  test('fromChunkListIndex no se sale de rango', () {
    final position = ReadingPosition.fromChunkListIndex(chunks, 99);
    expect(position.pageIndex, 2);
    expect(position.chunkIndex, 0);
  });
}
