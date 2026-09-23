/// "When the page URL starts with [urlPrefix], the next-chapter control is
/// the element matching [selector]."
class ChapterRule {
  const ChapterRule({
    required this.urlPrefix,
    required this.selector,
    this.label = '',
    this.enabled = true,
  });

  final String urlPrefix;
  final String selector;
  final String label; // text of the element when picked (for display only)
  final bool enabled;

  bool matches(String url) =>
      url.toLowerCase().startsWith(urlPrefix.toLowerCase());

  ChapterRule copyWith({String? urlPrefix, String? selector, String? label, bool? enabled}) =>
      ChapterRule(
        urlPrefix: urlPrefix ?? this.urlPrefix,
        selector: selector ?? this.selector,
        label: label ?? this.label,
        enabled: enabled ?? this.enabled,
      );

  Map<String, Object?> toJson() => {
        'prefix': urlPrefix,
        'selector': selector,
        'label': label,
        'enabled': enabled,
      };

  factory ChapterRule.fromJson(Map<String, dynamic> j) => ChapterRule(
        urlPrefix: j['prefix'] as String,
        selector: j['selector'] as String,
        label: (j['label'] as String?) ?? '',
        enabled: (j['enabled'] as bool?) ?? true,
      );
}

/// Candidate "URL starts with" values for a page.
class PrefixSuggestions {
  const PrefixSuggestions(this.site, this.folder, this.exact);
  final String site; // https://host/
  final String folder; // https://host/novel/123/
  final String exact; // https://host/novel/123/chapter-5   (no query/fragment)

  factory PrefixSuggestions.of(String url) {
    final u = Uri.tryParse(url);
    if (u == null || !u.hasAuthority) return PrefixSuggestions(url, url, url);
    final origin = '${u.scheme}://${u.authority}';
    final site = '$origin/';
    final path = u.path;
    if (path.isEmpty || path == '/') return PrefixSuggestions(site, site, site);
    final folder = '$origin${path.substring(0, path.lastIndexOf('/') + 1)}';
    return PrefixSuggestions(site, folder, '$origin$path');
  }
}