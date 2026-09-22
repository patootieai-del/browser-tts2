class UrlResolver {
  static final _scheme = RegExp(r'^[a-z][a-z0-9+.\-]*://', caseSensitive: false);
  static final _host = RegExp(r'^[\w\-]+(\.[\w\-]+)+(:\d+)?(/.*)?$');

  static String resolve(String input, String engineTemplate, String home) {
    final t = input.trim();
    if (t.isEmpty) return home;
    if (_scheme.hasMatch(t)) return t;
    if (!t.contains(' ') && _host.hasMatch(t)) return 'https://$t';
    if (t == 'localhost' || t.startsWith('localhost:')) return 'http://$t';
    return engineTemplate.replaceAll('%s', Uri.encodeQueryComponent(t));
  }
}