class LibraryEntry {
  LibraryEntry({
    required this.id,
    required this.name,
    required this.storedPath,
    required this.pageCount,
    required this.totalChunks,
    this.pageIndex = 0,
    this.chunkIndex = 0,
    this.lastOpenedIso,
    this.kind = 'pdf',
    this.favorite = false,
    this.finished = false,
  });

  final String id;

  /// 'pdf' | 'image' | 'txt'
  final String kind;
  String name;
  String storedPath;
  int pageCount;
  int totalChunks;
  int pageIndex;
  int chunkIndex;
  String? lastOpenedIso;
  bool favorite;
  bool finished;

  double get progress {
    if (pageCount <= 0) {
      return 0;
    }
    return ((pageIndex + 1) / pageCount).clamp(0, 1);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'storedPath': storedPath,
    'pageCount': pageCount,
    'totalChunks': totalChunks,
    'pageIndex': pageIndex,
    'chunkIndex': chunkIndex,
    'lastOpenedIso': lastOpenedIso,
    'kind': kind,
    'favorite': favorite,
    'finished': finished,
  };

  factory LibraryEntry.fromJson(Map<String, dynamic> json) {
    return LibraryEntry(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Documento',
      storedPath: json['storedPath'] as String? ?? '',
      pageCount: (json['pageCount'] as num?)?.toInt() ?? 0,
      totalChunks: (json['totalChunks'] as num?)?.toInt() ?? 0,
      pageIndex: (json['pageIndex'] as num?)?.toInt() ?? 0,
      chunkIndex: (json['chunkIndex'] as num?)?.toInt() ?? 0,
      lastOpenedIso: json['lastOpenedIso'] as String?,
      kind: json['kind'] as String? ?? 'pdf',
      favorite: json['favorite'] as bool? ?? false,
      finished: json['finished'] as bool? ?? false,
    );
  }
}

class LibraryData {
  LibraryData({List<LibraryEntry>? entries}) : entries = entries ?? [];

  final List<LibraryEntry> entries;

  Map<String, dynamic> toJson() => {
    'entries': entries.map((e) => e.toJson()).toList(),
  };

  factory LibraryData.fromJson(Map<String, dynamic> json) {
    final raw = json['entries'];
    if (raw is! List) {
      return LibraryData();
    }
    return LibraryData(
      entries: raw
          .whereType<Map>()
          .map((e) => LibraryEntry.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty)
          .toList(),
    );
  }
}
