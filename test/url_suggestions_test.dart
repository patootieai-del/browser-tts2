import 'package:flutter_test/flutter_test.dart';
import 'package:vox_browser/core/utils/url_suggestions.dart';

UrlSuggestion s(String url,
        {String title = '', int visits = 1, bool bm = false, DateTime? last}) =>
    UrlSuggestion(url: url, title: title, visits: visits, isBookmark: bm, lastVisit: last);

final now = DateTime(2025, 1, 15);

void main() {
  test('normalizeQuery strips scheme and www', () {
    expect(UrlRanker.normalizeQuery('https://www.Exa'), 'exa');
  });

  test('empty query -> nothing', () {
    expect(UrlRanker.rank([s('https://a.com')], '  '), isEmpty);
  });

  test('host prefix beats path/title substring', () {
    final r = UrlRanker.rank([
      s('https://news.site/articles/flutter-tips', title: 'Flutter tips'),
      s('https://flutter.dev', title: 'Flutter'),
    ], 'flut', now: now);
    expect(r.first.url, 'https://flutter.dev');
  });

  test('bookmarks are boosted', () {
    final r = UrlRanker.rank([
      s('https://a.com/docs', title: 'docs'),
      s('https://b.com/docs', title: 'docs', bm: true),
    ], 'docs', now: now);
    expect(r.first.url, 'https://b.com/docs');
  });

  test('frequent and recent visits rank higher', () {
    final r = UrlRanker.rank([
      s('https://old.com/x', title: 'x', visits: 1, last: DateTime(2024, 1, 1)),
      s('https://new.com/x', title: 'x', visits: 20, last: now),
    ], 'x', now: now);
    expect(r.first.url, 'https://new.com/x');
  });

  test('http/https/www/trailing-slash variants are merged', () {
    final r = UrlRanker.rank([
      s('http://www.a.com/', visits: 2),
      s('https://a.com', visits: 3),
    ], 'a.com', now: now);
    expect(r.length, 1);
    expect(r.single.visits, 5);
    expect(r.single.url, 'https://a.com');
  });

  test('multi-word queries require every word', () {
    final r = UrlRanker.rank([
      s('https://flutter.dev/docs', title: 'Flutter documentation'),
      s('https://flutter.dev/blog', title: 'Flutter blog'),
    ], 'flutter docs', now: now);
    expect(r.map((e) => e.url), ['https://flutter.dev/docs']);
  });

  test('respects the limit', () {
    final many = [for (var i = 0; i < 20; i++) s('https://site$i.com', title: 'site')];
    expect(UrlRanker.rank(many, 'site', limit: 6).length, 6);
  });
}