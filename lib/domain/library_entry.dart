/// Las formas de ver una misma hoja escaneada.
enum ScanVersion {
  original('Original'),
  scanned('Escaneado'),
  clean('En limpio');

  const ScanVersion(this.label);
  final String label;
}

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
    this.language,
    this.scanned = false,
    this.contentHash,
    this.originalPath,
    this.cleanPath,
    this.scanCopyPath,
  });

  final String id;

  /// 'pdf' | 'image' | 'txt'
  final String kind;

  /// Creado con «Escanear a PDF»: se lista aparte, en «Escaneados».
  final bool scanned;
  String name;
  String storedPath;
  int pageCount;
  int totalChunks;
  int pageIndex;
  int chunkIndex;
  String? lastOpenedIso;
  bool favorite;
  bool finished;

  /// Idioma elegido a mano ('es', 'en'…); null = detectarlo automáticamente.
  String? language;

  /// Huella del contenido al importarlo (SHA-256): el mismo archivo da la
  /// misma huella en cualquier aparato, así se reconoce al sincronizar. No
  /// cambia si después se edita. null hasta que se calcula.
  String? contentHash;

  /// PDF con las fotos tal como entraron al escáner. Solo escaneos nuevos.
  String? originalPath;

  /// PDF transcrito en limpio; null hasta que se arma.
  String? cleanPath;

  /// Foto importada ya pasada por el filtro de limpieza; null hasta que se arma.
  String? scanCopyPath;

  /// Las vistas que se ofrecen. Un PDF común ya es su propio «escaneado», y a
  /// un escaneo anterior a esta función no le quedó la foto original.
  List<ScanVersion> get scanVersions {
    if (kind != 'pdf' && kind != 'image') return const [];
    return [
      if (!scanned || originalPath != null) ScanVersion.original,
      if (scanned || kind == 'image') ScanVersion.scanned,
      ScanVersion.clean,
    ];
  }

  /// Dónde está esa vista; null si todavía hay que armarla.
  String? versionPath(ScanVersion version) => switch (version) {
    ScanVersion.original => scanned ? originalPath : storedPath,
    ScanVersion.scanned => kind == 'image' ? scanCopyPath : storedPath,
    ScanVersion.clean => cleanPath,
  };

  double get progress {
    if (pageCount <= 0) {
      return 0;
    }
    if (finished) {
      return 1;
    }
    // Progreso al inicio de la página actual: la página 1 de 2 es 0 %, no 50 %.
    return (pageIndex / pageCount).clamp(0, 1);
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
    'language': language,
    if (scanned) 'scanned': true,
    if (contentHash != null) 'hash': contentHash,
    if (originalPath != null) 'original': originalPath,
    if (cleanPath != null) 'cleanImage': cleanPath,
    if (scanCopyPath != null) 'scanSheet': scanCopyPath,
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
      language: json['language'] as String?,
      scanned: json['scanned'] as bool? ?? false,
      contentHash: json['hash'] as String?,
      originalPath: json['original'] as String?,
      cleanPath: json['cleanImage'] as String?,
      scanCopyPath: json['scanSheet'] as String?,
    );
  }
}

class LibraryData {
  LibraryData({List<LibraryEntry>? entries}) : entries = entries ?? [];

  final List<LibraryEntry> entries;

  Map<String, dynamic> toJson() => {'entries': entries.map((e) => e.toJson()).toList()};

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
