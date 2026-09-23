class PageScripts {
  /// Injected (main frame, document end). Reports *meaningful* DOM changes
  /// to Dart, debounced and throttled, without touching layout
  /// (textContent, not innerText).
  static const contentWatcher = r'''
(function () {
  if (window.__voxWatch) return;
  window.__voxWatch = true;
  var timer = null, lastSent = 0;
  function send() {
    timer = null; lastSent = Date.now();
    try {
      window.flutter_inappwebview.callHandler('voxContentChanged', location.href,
        document.body ? document.body.textContent.length : 0);
    } catch (e) {}
  }
  function schedule() {
    if (timer) clearTimeout(timer);
    var wait = Math.max(900, 1500 - (Date.now() - lastSent));
    timer = setTimeout(send, wait);
  }
  function start() {
    if (!document.body) return;
    new MutationObserver(function (muts) {
      for (var i = 0; i < muts.length; i++) {
        var m = muts[i];
        if (m.type === 'characterData' || m.addedNodes.length || m.removedNodes.length) {
          schedule(); return;
        }
      }
    }).observe(document.body, {childList: true, characterData: true, subtree: true});
  }
  if (document.body) start(); else document.addEventListener('DOMContentLoaded', start);
})();
''';
}