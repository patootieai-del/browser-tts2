import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/utils/text_map.dart';
import '../models/article.dart';
import 'dart:convert';
import '../models/page_probe.dart';

/// Everything ReaderController needs from a page. Faked in tests.
abstract class PageContentSource {
  /// [settle]: wait until the DOM stops changing before reading it.
  Future<Article?> extract({bool settle = false});

  /// Visible text nodes, in document order. Index == node id used by
  /// [highlight]. Must return exactly `node.data` (offsets depend on it).
  Future<List<String>> snapshotTextNodes();

  Future<bool> highlight(HighlightRange range);

  /// Remove the highlight. [release] also drops the page-side node list.
  Future<void> clearHighlight({bool release = false});

  Future<PageFingerprint?> fingerprint();
  Future<ClickResult> clickElement(String selector);
}

class ExtractionService {
  String? _readabilityJs;

  Future<String> _lib() async => _readabilityJs ??=
      await rootBundle.loadString('assets/js/readability.js');

  PageContentSource forController(InAppWebViewController c) =>
      WebViewPageSource(c, _lib);
}

class WebViewPageSource implements PageContentSource {
  WebViewPageSource(this._c, this._lib);
  final InAppWebViewController _c;
  final Future<String> Function() _lib;

  @override
  Future<List<String>> snapshotTextNodes() async {
    const script = r'''
      (function () {
        var nodes = [], texts = [], cache = new Map();
        var skip = {SCRIPT:1, STYLE:1, NOSCRIPT:1, TEMPLATE:1, TEXTAREA:1, HEAD:1};
        function visible(el) {
          if (cache.has(el)) return cache.get(el);
          var ok = !skip[el.tagName];
          if (ok) ok = el.checkVisibility
              ? el.checkVisibility({visibilityProperty: true})
              : el.getClientRects().length > 0;
          cache.set(el, ok);
          return ok;
        }
        if (!document.body) return [];
        var w = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT), n;
        while ((n = w.nextNode())) {
          var p = n.parentElement;
          if (!p || !n.data || !/\S/.test(n.data) || !visible(p)) continue;
          nodes.push(n); texts.push(n.data);
        }
        window.__voxNodes = nodes;
        return texts;
      })();
      ''';
    final r = await _c.evaluateJavascript(source: script);
    if (r is! List) return const [];
    return r.map((e) => e.toString()).toList(growable: false);
  }

  @override
  Future<bool> highlight(HighlightRange r) async {
    try {
      final res = await _c.evaluateJavascript(source: '''
        (function (sn, so, en, eo) {
          var N = window.__voxNodes;
          if (!N) return false;
          var a = N[sn], b = N[en];
          if (!a || !b || !a.isConnected || !b.isConnected) return false;
          try {
            var r = document.createRange();
            r.setStart(a, Math.min(so, a.length));
            r.setEnd(b, Math.min(eo, b.length));
            if (window.CSS && CSS.highlights && window.Highlight) {
              if (!document.getElementById('__vox_style')) {
                var s = document.createElement('style'); s.id = '__vox_style';
                s.textContent = '::highlight(vox){background-color:rgba(255,213,79,.6);color:inherit;}';
                document.head.appendChild(s);
              }
              CSS.highlights.set('vox', new Highlight(r));
            } else {
              var sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(r);
              window.__voxSel = true;
            }
            var rect = r.getBoundingClientRect();
            if (rect.top < 80 || rect.bottom > window.innerHeight - 80) {
              window.scrollBy({top: rect.top - window.innerHeight * 0.35,
                              behavior: 'smooth'});
            }
            return true;
          } catch (e) { return false; }
        })(${r.startNode}, ${r.startOffset}, ${r.endNode}, ${r.endOffset});
        ''');
      return res == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> clearHighlight({bool release = false}) async {
    try {
      await _c.evaluateJavascript(source: '''
        (function () {
          if (window.CSS && CSS.highlights) CSS.highlights.delete('vox');
          if (window.__voxSel) { window.getSelection().removeAllRanges(); window.__voxSel = false; }
          ${release ? 'window.__voxNod' 'es = null;' : ''}
        })();
        ''');
    } catch (_) {/* controller may already be disposed */}
  }

  Future<void> _waitForSettle() async {
    try {
      await _c.callAsyncJavaScript(functionBody: '''
        return await new Promise(function (resolve) {
          var quiet = 350, max = 4000, timer = null, cap = null, done = false, obs = null;
          function finish() {
            if (done) return; done = true;
            if (obs) obs.disconnect();
            clearTimeout(timer); clearTimeout(cap); resolve(true);
          }
          obs = new MutationObserver(function () {
            clearTimeout(timer); timer = setTimeout(finish, quiet);
          });
          obs.observe(document.documentElement,
              {childList: true, subtree: true, characterData: true});
          timer = setTimeout(finish, quiet);
          cap = setTimeout(finish, max);
        });
      ''');
    } catch (_) {/* unsupported / disposed: extract immediately */}
  }

  @override
  Future<Article?> extract({bool settle = false}) async {
    try {
      if (settle) await _waitForSettle();
      final url = (await _c.getUrl())?.toString() ?? '';
      final lib = await _lib();
      final script = '''
        (function () {
          var L = document.body ? document.body.textContent.length : 0;
          try {
            var R = (function () { $lib
              ; return Readability; })();
            var clone = document.cloneNode(true);
            var a = new R(clone, {charThreshold: 250}).parse();
            clone = null;
            if (a && a.textContent && a.textContent.trim().length > 200) {
              return { title: a.title || document.title, textContent: a.textContent,
                      byline: a.byline || '', excerpt: a.excerpt || '', domLength: L };
            }
          } catch (e) {}
          var b = document.body ? document.body.cloneNode(true) : null;
          if (!b) return null;
          b.querySelectorAll('script,style,noscript,nav,header,footer,aside,form,' +
            'iframe,svg,[aria-hidden="true"],[role="navigation"],[role="banner"]')
            .forEach(function (n) { n.remove(); });
          return { title: document.title, textContent: (b.innerText || '').trim(),
                  byline: '', excerpt: '', domLength: L };
        })();
        ''';
      final r = await _c.evaluateJavascript(source: script);
      if (r is! Map) return null;
      final a = Article.fromJson(r, url);
      return a.isEmpty ? null : a;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<PageFingerprint?> fingerprint() async {
    try {
      final r = await _c.evaluateJavascript(source: r'''
(function () {
  var t = document.body ? document.body.textContent : '';
  return {url: location.href, title: document.title, len: t.length,
          head: t.slice(0, 300), tail: t.slice(-300)};
})();''');
      if (r is! Map) return null; // page is mid-navigation
      return PageFingerprint(
        url: '${r['url']}',
        title: '${r['title']}',
        len: (r['len'] as num).toInt(),
        head: '${r['head']}',
        tail: '${r['tail']}',
      );
    } catch (_) {
      return null;
    }
  }

  /// Finds the element, verifies it is really clickable, then clicks it.
  @override
  Future<ClickResult> clickElement(String selector) async {
    try {
      final r = await _c.evaluateJavascript(source: '''
(function (sel) {
  var el = null;
  try { el = document.querySelector(sel); }
  catch (e) { return {status: 'notFound', reason: 'invalid selector'}; }
  if (!el) return {status: 'notFound'};
  function bad(r) { return {status: 'notClickable', reason: r}; }
  if (el.disabled) return bad('it is disabled');
  if (el.getAttribute('aria-disabled') === 'true') return bad('it is marked as disabled');
  var cn = (typeof el.className === 'string') ? el.className : '';
  if (/(^|[\\s_-])disabled([\\s_-]|\$)/i.test(cn)) return bad('it looks disabled');
  var cs = getComputedStyle(el);
  if (cs.display === 'none' || cs.visibility === 'hidden' || parseFloat(cs.opacity) === 0)
    return bad('it is hidden');
  if (cs.pointerEvents === 'none') return bad('it does not accept clicks');
  var r = el.getBoundingClientRect();
  if (r.width < 1 || r.height < 1) return bad('it has no size');
  el.scrollIntoView({block: 'center', inline: 'center'});
  r = el.getBoundingClientRect();
  var x = r.left + r.width / 2, y = r.top + r.height / 2;
  var top = document.elementFromPoint(x, y);
  if (top && top !== el && !el.contains(top) && !top.contains(el))
    return bad('another element is covering it');
  ['mousedown', 'mouseup', 'click'].forEach(function (type) {
    el.dispatchEvent(new MouseEvent(type, {bubbles: true, cancelable: true,
      view: window, clientX: x, clientY: y}));
  });
  var a = el.closest ? el.closest('a') : null;
  return {status: 'clicked', href: a ? a.href : ''};
})(${jsonEncode(selector)});
''');
      if (r is! Map)
        return const ClickResult(ClickStatus.notFound, 'no response from page');
      switch (r['status']) {
        case 'clicked':
          return ClickResult.clicked;
        case 'notClickable':
          return ClickResult(ClickStatus.notClickable, r['reason']?.toString());
        default:
          return ClickResult(ClickStatus.notFound, r['reason']?.toString());
      }
    } catch (_) {
      return const ClickResult(ClickStatus.notFound, 'page not available');
    }
  }
}
