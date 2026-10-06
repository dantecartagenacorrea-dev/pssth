class ReadingPosition {
  const ReadingPosition({this.pageIndex = 0, this.chunkIndex = 0});

  final int pageIndex;
  final int chunkIndex;

  ReadingPosition copyWith({int? pageIndex, int? chunkIndex}) {
    return ReadingPosition(
      pageIndex: pageIndex ?? this.pageIndex,
      chunkIndex: chunkIndex ?? this.chunkIndex,
    );
  }

  int resolveChunkListIndex(List<({int pageIndex, int chunkIndex})> chunks) {
    if (chunks.isEmpty) {
      return 0;
    }
    for (var i = 0; i < chunks.length; i++) {
      if (chunks[i].pageIndex == pageIndex && chunks[i].chunkIndex == chunkIndex) {
        return i;
      }
    }
    for (var i = 0; i < chunks.length; i++) {
      if (chunks[i].pageIndex == pageIndex) {
        return i;
      }
    }
    for (var i = 0; i < chunks.length; i++) {
      if (chunks[i].pageIndex > pageIndex) {
        return i;
      }
    }
    return chunks.length - 1;
  }

  static ReadingPosition fromChunkListIndex(
    List<({int pageIndex, int chunkIndex})> chunks,
    int index,
  ) {
    if (chunks.isEmpty) {
      return const ReadingPosition();
    }
    final clamped = index.clamp(0, chunks.length - 1);
    final chunk = chunks[clamped];
    return ReadingPosition(pageIndex: chunk.pageIndex, chunkIndex: chunk.chunkIndex);
  }
}
