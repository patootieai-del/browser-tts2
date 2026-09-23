import 'dart:math' as math;

class UrlSuggestion {
  const UrlSuggestion({
    required this.url,
    required this.title,
    this.visits = 0,
    this.lastVisit,
    this.isBookmark = false,
  });

  final String url;
  final String title;
  final int visits;
  final DateTime? lastVisit;
  final bool isBookmark;

  /// Scheme-less, www-less form for display.
  String get display => UrlRanker.key(url);
}

/// Pure ranking logic (unit-tested). The database only pre-filters.
class UrlRanker {
  static final _scheme = RegExp(r'^[a-z][a-z0-9+.\-]*://');

  /// Normalised identity of a URL: no scheme, no "www.", no trailing "/".
  static String key(String url) {
    var s = url.trim().toLowerCase().replaceFirst(_scheme, '');
    s = s.replaceFirst(RegExp(r'^www\.'), '');
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  static String normalizeQuery(String q) => key(q.trim());

  static String _host(String key) => key.split(RegExp(r'[/?#]')).first;

  static List<UrlSuggestion> rank(
    Iterable<UrlSuggestion> candidates,
    String query, {
    int limit = 6,
    DateTime? now,
  }) {
    final q = normalizeQuery(query);
    if (q.isEmpty) return const [];
    final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final clock = now ?? DateTime.now();

    // 1. Merge duplicates (http/https, www, trailing slash).
    final merged = <String, UrlSuggestion>{};
    for (final c in candidates) {
      final k = key(c.url);
      final prev = merged[k];
      if (prev == null) {
        merged[k] = c;
        continue;
      }
      final base = (c.visits > prev.visits ||
              (c.visits == prev.visits && c.url.startsWith('https')))
          ? c
          : prev;
      final last = [prev.lastVisit, c.lastVisit]
          .whereType<DateTime>()
          .fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
      merged[k] = UrlSuggestion(
        url: base.url,
        title: base.title.isNotEmpty ? base.title : (prev.title + c.title),
        visits: prev.visits + c.visits,
        lastVisit: last,
        isBookmark: prev.isBookmark || c.isBookmark,
      );
    }

    // 2. Score.
    final scored = <(double, UrlSuggestion)>[];
    for (final s in merged.values) {
      final k = key(s.url);
      final t = s.title.toLowerCase();
      if (!tokens.every((tk) => k.contains(tk) || t.contains(tk))) continue;

      final h = _host(k);
      var score = 5.0;
      if (h.startsWith(q)) {
        score = 100;
      } else if (k.startsWith(q)) {
        score = 90;
      } else if (h.contains(q)) {
        score = 50;
      } else if (t.startsWith(q)) {
        score = 40;
      } else if (k.contains(q)) {
        score = 20;
      } else if (t.contains(q)) {
        score = 15;
      }
      if (s.isBookmark) score += 25;
      score += math.log(s.visits + 1) * 10;
      final last = s.lastVisit;
      if (last != null) {
        final age = clock.difference(last);
        if (age < const Duration(days: 1)) {
          score += 10;
        } else if (age < const Duration(days: 7)) {
          score += 5;
        }
      }
      score -= k.length * 0.05; // mild preference for short/home URLs
      scored.add((score, s));
    }

    scored.sort((a, b) {
      final c = b.$1.compareTo(a.$1);
      if (c != 0) return c;
      return (b.$2.lastVisit ?? DateTime(0))
          .compareTo(a.$2.lastVisit ?? DateTime(0));
    });
    return scored.take(limit).map((e) => e.$2).toList();
  }

  /// Newest-first history rows -> distinct pages, most recent first.
  static List<UrlSuggestion> recent(Iterable<UrlSuggestion> newestFirst,
      {int limit = 12}) {
    final seen = <String>{};
    final out = <UrlSuggestion>[];
    for (final s in newestFirst) {
      if (seen.add(key(s.url))) {
        out.add(s);
        if (out.length >= limit) break;
      }
    }
    return out;
  }
}
