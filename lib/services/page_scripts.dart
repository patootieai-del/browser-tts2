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

  /// Element picker: intercepts the next tap, outlines the element and reports
  /// a stable CSS selector. Scrolling still works (only `click` is captured).
  static const picker = r'''
    (function () {
      if (window.__voxPicker) { window.__voxPicker.start(); return; }
      var cur = null;

      if (!document.getElementById('__vox_pick_style')) {
        var st = document.createElement('style'); st.id = '__vox_pick_style';
        st.textContent = '[data-vox-pick]{outline:3px solid #ff6d00!important;outline-offset:2px!important;}';
        document.head.appendChild(st);
      }

      function esc(s) { return (window.CSS && CSS.escape) ? CSS.escape(s) : String(s).replace(/([^\w-])/g, '\\$1'); }
      function attr(s) { return String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"'); }
      function stableClass(c) {
        return c.length <= 30 && !/\d/.test(c) &&
          !/^(active|current|hover|focus|disabled|selected|open|show|hide|hidden|visible)$/i.test(c);
      }
      // A selector segment that avoids ids/classes that look generated.
      function seg(el) {
        if (el.id && el.id.length <= 40 && !/\d{3,}/.test(el.id)) return '#' + esc(el.id);
        var s = el.tagName.toLowerCase();
        var rel = el.getAttribute('rel');
        if (rel && rel.length < 20) s += '[rel="' + attr(rel) + '"]';
        var al = el.getAttribute('aria-label');
        if (al && al.length <= 40) s += '[aria-label="' + attr(al) + '"]';
        Array.prototype.filter.call(el.classList, stableClass).slice(0, 3)
          .forEach(function (c) { s += '.' + esc(c); });
        return s;
      }
      function unique(sel, el) {
        try { var l = document.querySelectorAll(sel); return l.length === 1 && l[0] === el; }
        catch (e) { return false; }
      }
      function cssPath(el) {
        var parts = [], node = el, depth = 0;
        while (node && node.nodeType === 1 && node !== document.documentElement && depth < 8) {
          var s = seg(node), p = node.parentElement;
          if (s.charAt(0) !== '#' && p) {
            var clash = false;
            try { clash = Array.prototype.some.call(p.children, function (c) { return c !== node && c.matches(s); }); } catch (e) {}
            if (clash) {
              var idx = Array.prototype.filter.call(p.children, function (c) { return c.tagName === node.tagName; }).indexOf(node) + 1;
              s += ':nth-of-type(' + idx + ')';
            }
          }
          parts.unshift(s);
          var sel = parts.join(' > ');
          if (unique(sel, el)) return sel;
          node = p; depth++;
        }
        return parts.join(' > ');
      }
      function clickable(el) {
        return el.closest('a,button,[role="button"],input[type="button"],input[type="submit"],[onclick]') || el;
      }
      function mark(el) {
        if (cur) cur.removeAttribute('data-vox-pick');
        cur = el; el.setAttribute('data-vox-pick', '1');
      }
      function report() {
        if (!cur) return;
        var a = cur.closest ? cur.closest('a') : null;
        var p = cur.parentElement;
        try {
          window.flutter_inappwebview.callHandler('voxElementPicked', {
            selector: cssPath(cur),
            label: (cur.innerText || cur.value || cur.getAttribute('aria-label') || cur.title || '').trim().slice(0, 60),
            tag: cur.tagName.toLowerCase(),
            href: a ? a.href : '',
            url: location.href,
            canGoUp: !!(p && p !== document.body && p !== document.documentElement)
          });
        } catch (e) {}
      }
      function onClick(e) {
        e.preventDefault(); e.stopPropagation(); e.stopImmediatePropagation();
        mark(clickable(e.target)); report();
      }
      window.__voxPicker = {
        start: function () { document.addEventListener('click', onClick, true); },
        stop: function () {
          document.removeEventListener('click', onClick, true);
          if (cur) { cur.removeAttribute('data-vox-pick'); cur = null; }
        },
        up: function () {
          if (cur && cur.parentElement && cur.parentElement !== document.body) {
            mark(cur.parentElement); report();
          }
        }
      };
      window.__voxPicker.start();
    })();
    ''';
}
