class HistoryEntry {
  final int? id;
  final String url;
  final String title;
  final DateTime visitedAt;

  const HistoryEntry({
    this.id,
    required this.url,
    required this.title,
    required this.visitedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'url': url,
        'title': title,
        'visited_at': visitedAt.millisecondsSinceEpoch,
      };

  factory HistoryEntry.fromMap(Map<String, Object?> m) => HistoryEntry(
        id: m['id'] as int?,
        url: m['url'] as String,
        title: m['title'] as String,
        visitedAt:
            DateTime.fromMillisecondsSinceEpoch(m['visited_at'] as int),
      );
}