/// A DOM Range expressed as indices into the page's visible text-node list.
class HighlightRange {
  const HighlightRange({
    required this.startNode,
    required this.startOffset,
    required this.endNode,
    required this.endOffset,
    required this.flatStart,
    required this.flatEnd,
  });

  final int startNode;
  final int startOffset; // UTF-16 offset inside startNode.data
  final int endNode;
  final int endOffset; // exclusive
  final int flatStart; // position in the canonical string (for cursoring)
  final int flatEnd;

  @override
  String toString() =>
      'HighlightRange($startNode:$startOffset -> $endNode:$endOffset)';
}

/// Locates speech chunks inside the page's visible text nodes.
///
/// Both the page text and the chunk are reduced to a canonical form:
/// lower-cased letters and digits only, with URLs removed. That makes
/// matching immune to whitespace, NBSP, punctuation, smart quotes, the
/// period added after the title, and to sentence merging in the chunker.
///
/// Rule: prefer NO highlight over a WRONG highlight -> returns null when
/// there is no confident match.
class TextMap {
  TextMap(List<String> nodeTexts) {
    final flat = StringBuffer();
    for (var n = 0; n < nodeTexts.length; n++) {
      for (final m in _kept(nodeTexts[n])) {
        final lower = m[0]!.toLowerCase();
        // toLowerCase can change length (e.g. 'İ'); map every unit.
        for (var k = 0; k < lower.length; k++) {
          _node.add(n);
          _start.add(m.start);
          _end.add(m.end);
        }
        flat.write(lower);
      }
    }
    _flat = flat.toString();
  }

  static final _url = RegExp(r'https?://\S+');
  static final _alnum = RegExp(r'[\p{L}\p{N}]', unicode: true);

  late final String _flat;
  final List<int> _node = [];
  final List<int> _start = [];
  final List<int> _end = [];
  final Map<int, HighlightRange> _found = {};

  int get length => _flat.length;

  /// Letter/digit matches that are not inside a URL.
  static Iterable<Match> _kept(String t) sync* {
    final urls = _url.allMatches(t).toList();
    var u = 0;
    for (final m in _alnum.allMatches(t)) {
      while (u < urls.length && urls[u].end <= m.start) {
        u++;
      }
      if (u < urls.length && m.start >= urls[u].start) continue;
      yield m;
    }
  }

  static String canon(String s) {
    final b = StringBuffer();
    for (final m in _kept(s)) {
      b.write(m[0]!.toLowerCase());
    }
    return b.toString();
  }

  /// Locate chunk number [index]. Searches forward from the end of the
  /// nearest earlier chunk that was already located, so repeated phrases
  /// ("Share this", "Read more") resolve to the right occurrence.
  HighlightRange? locateForIndex(int index, String chunk) {
    final cached = _found[index];
    if (cached != null) return cached;

    var from = 0;
    var best = -1;
    for (final k in _found.keys) {
      if (k < index && k > best) best = k;
    }
    if (best >= 0) from = _found[best]!.flatEnd;

    final r = locate(chunk, from: from);
    if (r != null) _found[index] = r;
    return r;
  }

  HighlightRange? locate(String chunk, {int from = 0}) {
    final c = canon(chunk);
    if (c.isEmpty) return null;

    var i = _flat.indexOf(c, from);
    if (i < 0 && from > 0) i = _flat.indexOf(c);
    if (i >= 0) return _range(i, i + c.length);

    // Fallback for chunks whose middle differs from the DOM (inline ads,
    // stripped widgets): anchor on head and tail, but only if the span
    // between them is plausibly the same length.
    const a = 30;
    if (c.length > 2 * a) {
      final head = c.substring(0, a);
      final tail = c.substring(c.length - a);
      var h = _flat.indexOf(head, from);
      if (h < 0 && from > 0) h = _flat.indexOf(head);
      if (h >= 0) {
        final t = _flat.indexOf(tail, h + a);
        if (t >= 0 && (t + a - h) <= c.length * 1.5 + 50) {
          return _range(h, t + a);
        }
      }
    }
    return null;
  }

  HighlightRange _range(int s, int e) => HighlightRange(
        startNode: _node[s],
        startOffset: _start[s],
        endNode: _node[e - 1],
        endOffset: _end[e - 1],
        flatStart: s,
        flatEnd: e,
      );
}