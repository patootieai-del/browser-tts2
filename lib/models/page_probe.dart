/// Cheap "did the page change?" signature.
class PageFingerprint {
  const PageFingerprint({
    required this.url,
    required this.title,
    required this.len,
    required this.head,
    required this.tail,
  });
  final String url, title, head, tail;
  final int len;

  @override
  bool operator ==(Object o) =>
      o is PageFingerprint &&
      o.url == url &&
      o.title == title &&
      o.len == len &&
      o.head == head &&
      o.tail == tail;

  @override
  int get hashCode => Object.hash(url, title, len, head, tail);
}

enum ClickStatus { clicked, notFound, notClickable }

class ClickResult {
  const ClickResult(this.status, [this.reason]);
  final ClickStatus status;
  final String? reason;

  static const clicked = ClickResult(ClickStatus.clicked);
  static const notFound = ClickResult(ClickStatus.notFound);
}