class Article {
  final String title;
  final String url;
  final String text;
  final String? byline;
  final String? excerpt;

  const Article({
    required this.title,
    required this.url,
    required this.text,
    this.byline,
    this.excerpt,
  });

  bool get isEmpty => text.trim().isEmpty;

  factory Article.fromJson(Map<dynamic, dynamic> j, String url) => Article(
        title: (j['title'] ?? '').toString(),
        url: url,
        text: (j['textContent'] ?? '').toString(),
        byline: j['byline']?.toString(),
        excerpt: j['excerpt']?.toString(),
      );
}