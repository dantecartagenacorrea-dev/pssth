class Bookmark {
  Bookmark({
    required this.id,
    required this.documentId,
    required this.pageIndex,
    required this.chunkIndex,
    required this.label,
    required this.createdIso,
  });

  final String id;
  final String documentId;
  final int pageIndex;
  final int chunkIndex;
  final String label;
  final String createdIso;

  Map<String, dynamic> toJson() => {
        'id': id,
        'documentId': documentId,
        'pageIndex': pageIndex,
        'chunkIndex': chunkIndex,
        'label': label,
        'createdIso': createdIso,
      };

  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
        id: j['id'] as String? ?? '',
        documentId: j['documentId'] as String? ?? '',
        pageIndex: (j['pageIndex'] as num?)?.toInt() ?? 0,
        chunkIndex: (j['chunkIndex'] as num?)?.toInt() ?? 0,
        label: j['label'] as String? ?? '',
        createdIso: j['createdIso'] as String? ?? '',
      );
}
