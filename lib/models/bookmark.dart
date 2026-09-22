class Bookmark {
  final int? id;
  final String url;
  final String title;
  final String folder;
  final DateTime createdAt;

  const Bookmark({
    this.id,
    required this.url,
    required this.title,
    this.folder = 'Unsorted',
    required this.createdAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'url': url,
        'title': title,
        'folder': folder,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory Bookmark.fromMap(Map<String, Object?> m) => Bookmark(
        id: m['id'] as int?,
        url: m['url'] as String,
        title: m['title'] as String,
        folder: (m['folder'] as String?) ?? 'Unsorted',
        createdAt:
            DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );
}