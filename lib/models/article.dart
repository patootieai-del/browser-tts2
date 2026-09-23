class Article {
  final String title;
  final String url;
  final String text;
  final String? byline;
  final String? excerpt;
  final int domLength;

  const Article({
    required this.title,
    required this.url,
    required this.text,
    this.byline,
    this.excerpt,
    this.domLength = 0, // document.body.textContent.length at extraction time
  });

  bool get isEmpty => text.trim().isEmpty;

  factory Article.fromJson(Map<dynamic, dynamic> j, String url) => Article(
        title: (j['title'] ?? '').toString(),
        url: url,
        text: (j['textContent'] ?? '').toString(),
        byline: j['byline']?.toString(),
        excerpt: j['excerpt']?.toString(),
        domLength: (j['domLength'] as num?)?.toInt() ?? 0,
      );
}