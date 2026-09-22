import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../models/article.dart';

class ExtractionService {
  String? _readabilityJs;

  Future<String> _js() async =>
      _readabilityJs ??= await rootBundle.loadString('assets/js/readability.js');

  /// Everything lives inside one IIFE: nothing is left on `window`, so the
  /// page can garbage-collect the library and the cloned document.
  Future<Article?> extract(InAppWebViewController c) async {
    try {
      final url = (await c.getUrl())?.toString() ?? '';
      final lib = await _js();

      final script = '''
(function () {
  try {
    var R = (function () { $lib
      ; return Readability; })();
    var clone = document.cloneNode(true);
    var a = new R(clone, {charThreshold: 250}).parse();
    clone = null;
    if (a && a.textContent && a.textContent.trim().length > 200) {
      return { title: a.title || document.title, textContent: a.textContent,
               byline: a.byline || '', excerpt: a.excerpt || '' };
    }
  } catch (e) {}
  var b = document.body ? document.body.cloneNode(true) : null;
  if (!b) return null;
  b.querySelectorAll('script,style,noscript,nav,header,footer,aside,form,' +
    'iframe,svg,[aria-hidden="true"],[role="navigation"],[role="banner"]')
    .forEach(function (n) { n.remove(); });
  return { title: document.title, textContent: (b.innerText || '').trim(),
           byline: '', excerpt: '' };
})();
''';
      final result = await c.evaluateJavascript(source: script);
      if (result is! Map) return null;
      final a = Article.fromJson(result, url);
      return a.isEmpty ? null : a;
    } catch (_) {
      return null; // controller may already be disposed
    }
  }

  Future<void> highlight(InAppWebViewController c, String snippet) async {
    try {
      final end = snippet.length < 120 ? snippet.length : 120;
      final needle = jsonEncode(snippet.substring(0, end).replaceAll('\n', ' '));
      await c.evaluateJavascript(source: '''
(function(){
  document.querySelectorAll('.__vox_hl').forEach(function(e){
    e.classList.remove('__vox_hl'); });
  if (!document.getElementById('__vox_style')) {
    var s = document.createElement('style'); s.id = '__vox_style';
    s.textContent = '.__vox_hl{background:rgba(255,213,79,.55)!important;border-radius:3px;}';
    document.head.appendChild(s);
  }
  var target = ($needle).trim();
  if (!target) return;
  var probe = target.slice(0, 40);
  var w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT), n;
  while ((n = w.nextNode())) {
    if (n.nodeValue && n.nodeValue.indexOf(probe) !== -1 && n.parentElement) {
      n.parentElement.classList.add('__vox_hl');
      n.parentElement.scrollIntoView({behavior:'smooth', block:'center'});
      return;
    }
  }
})();
''');
    } catch (_) {}
  }

  Future<void> clearHighlight(InAppWebViewController c) async {
    try {
      await c.evaluateJavascript(
          source: "document.querySelectorAll('.__vox_hl')"
              ".forEach(function(e){e.classList.remove('__vox_hl');});");
    } catch (_) {}
  }
}