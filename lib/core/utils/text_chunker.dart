/// Splits article text into speakable chunks.
///
/// Rules:
///  - Prefer sentence boundaries (. ! ? … and CJK 。！？).
///  - Never exceed [maxChars] (Android TTS silently truncates ~4000 chars).
///  - Merge very short fragments (e.g. "Mr.") into the next sentence.
class TextChunker {
  static const int maxChars = 900; // short chunks = responsive skip/seek
  static const int minChars = 40;

  static final RegExp _sentenceEnd =
      RegExp(r'(?<=[.!?…。！？])\s+|(?<=\n)\s*\n+');

  static final RegExp _abbrev = RegExp(
      r'\b(Mr|Mrs|Ms|Dr|Prof|Sr|Jr|St|vs|etc|e\.g|i\.e|Inc|Ltd|Fig|No)\.$',
      caseSensitive: false);

  static List<String> chunk(String raw) {
    final text = _normalise(raw);
    if (text.isEmpty) return const [];

    final pieces = text.split(_sentenceEnd).where((s) => s.trim().isNotEmpty);

    final out = <String>[];
    final buf = StringBuffer();

    void flush() {
      final s = buf.toString().trim();
      if (s.isNotEmpty) out.add(s);
      buf.clear();
    }

    for (final piece in pieces) {
      final s = piece.trim();

      // Hard-split monster sentences (tables, minified junk).
      if (s.length > maxChars) {
        flush();
        out.addAll(_hardSplit(s));
        continue;
      }

      if (buf.length + s.length + 1 > maxChars) flush();
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(s);

      final endsAbbrev = _abbrev.hasMatch(s);
      if (buf.length >= minChars && !endsAbbrev) flush();
    }
    flush();
    return out;
  }

  static String _normalise(String t) => t
      .replaceAll('\u00A0', ' ')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      // Strip bare URLs — nobody wants "h-t-t-p-s colon slash slash".
      .replaceAll(RegExp(r'https?://\S+'), '')
      .trim();

  static List<String> _hardSplit(String s) {
    final out = <String>[];
    var start = 0;
    while (start < s.length) {
      var end = (start + maxChars).clamp(0, s.length);
      if (end < s.length) {
        final sp = s.lastIndexOf(' ', end);
        if (sp > start + minChars) end = sp;
      }
      out.add(s.substring(start, end).trim());
      start = end;
    }
    return out.where((e) => e.isNotEmpty).toList();
  }
}