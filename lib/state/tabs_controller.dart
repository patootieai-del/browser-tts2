import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_config.dart';
import '../models/browser_tab.dart';
import 'reader_controller.dart';

class TabsController extends ChangeNotifier with WidgetsBindingObserver {
  TabsController(this._reader) {
    WidgetsBinding.instance.addObserver(this);
  }

  static const _kSession = 'tabs_v1';

  final ReaderController _reader;
  final List<BrowserTab> _tabs = [];
  int _active = 0;
  bool _ready = false;
  bool _disposed = false;
  Timer? _saveTimer;

  // ------------------------------------------------------------ getters
  bool get ready => _ready;
  int get count => _tabs.length;
  List<BrowserTab> get tabs => List.unmodifiable(_tabs);
  List<BrowserTab> get liveTabs =>
      _tabs.where((t) => t.live).toList(growable: false);
  BrowserTab get active => _tabs[_active];
  bool isActive(BrowserTab t) =>
      _ready && _tabs.isNotEmpty && identical(_tabs[_active], t);
  bool get hasIncognito => _tabs.any((t) => t.incognito);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ------------------------------------------------------------ session
  Future<void> restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kSession);
      if (raw != null) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        for (final j in (m['tabs'] as List)) {
          _tabs.add(BrowserTab.fromJson(j as Map<String, dynamic>));
        }
        final idx = _tabs.indexWhere((t) => t.id == m['active']);
        _active = idx < 0 ? 0 : idx;
      }
    } catch (_) {
      _tabs.clear();
    }
    if (_disposed) return;
    if (_tabs.isEmpty) {
      _tabs.add(BrowserTab());
      _active = 0;
    }
    _ready = true;
    _activate(_active);
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _saveNow);
  }

  Future<void> _saveNow() async {
    if (!_ready) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _kSession,
        jsonEncode({
          'active': active.id,
          'tabs': _tabs.where((t) => !t.incognito).map((t) => t.toJson()).toList(),
        }),
      );
    } catch (_) {}
  }

  // ---------------------------------------------------- activation / LRU
  void _activate(int i) {
    _active = i.clamp(0, _tabs.length - 1);
    final t = _tabs[_active];
    t.lastActive = DateTime.now();
    if (!t.live) t.createRuntime();
    _reader.bind(t.controller); // null until the WebView is created
    _enforceLiveLimit();
    _notify();
    _scheduleSave();
  }

  void _enforceLiveLimit() {
    final others = _tabs
        .where((t) => t.live && !identical(t, active))
        .toList()
      ..sort((a, b) => b.lastActive.compareTo(a.lastActive));
    for (final t in others.skip(AppConfig.maxLiveTabs - 1)) {
      unawaited(_discard(t));
    }
  }

  /// Destroy the native WebView but keep the tab (url, title, scroll).
  Future<void> _discard(BrowserTab t) async {
    if (!t.live || t.closed) return;
    try {
      final y = await t.controller?.getScrollY();
      t.pendingScrollY = (y ?? 0).toDouble();
    } catch (_) {}
    // Re-check after the await: it may have been activated or closed.
    if (_disposed || t.closed || !t.live || isActive(t)) return;
    t.live = false;
    _notify(); // rebuild removes the InAppWebView widget
    _afterFrame(t.releaseRuntime);
  }

  void _afterFrame(VoidCallback cb) {
    WidgetsBinding.instance.addPostFrameCallback((_) => cb());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  // ------------------------------------------------------------ tab ops
  BrowserTab? _byId(String id) {
    for (final t in _tabs) {
      if (t.id == id) return t;
    }
    return null;
  }

  BrowserTab newTab({
    String? url,
    bool incognito = false,
    bool desktop = false,
    String? title,
  }) {
    if (_tabs.length >= AppConfig.maxTabs) {
      final victim = _tabs.firstWhere((t) => !isActive(t));
      _removeAndRetire([victim]);
    }
    final t = BrowserTab(
        url: url, incognito: incognito, desktop: desktop, title: title ?? 'New tab');
    _tabs.insert((_active + 1).clamp(0, _tabs.length), t);
    _activate(_tabs.indexOf(t));
    return t;
  }

  void select(String id) {
    final i = _tabs.indexWhere((t) => t.id == id);
    if (i >= 0) _activate(i);
  }

  void duplicate(String id) {
    final src = _byId(id);
    if (src == null) return;
    final t = BrowserTab(
      url: src.url,
      title: src.title,
      incognito: src.incognito,
      desktop: src.desktop,
    )..pendingScrollY = src.pendingScrollY;
    _tabs.insert(_tabs.indexOf(src) + 1, t);
    _activate(_tabs.indexOf(t));
  }

  void closeTab(String id) {
    final i = _tabs.indexWhere((t) => t.id == id);
    if (i < 0) return;
    final t = _tabs.removeAt(i);
    if (_tabs.isEmpty) {
      _tabs.add(BrowserTab());
      _active = 0;
    } else if (i < _active) {
      _active--;
    } else if (i == _active) {
      _active = i.clamp(0, _tabs.length - 1);
    }
    _activate(_active);
    _retire([t]);
  }

  void closeOthers(String id) {
    final keep = _byId(id);
    if (keep == null) return;
    final removed = _tabs.where((t) => !identical(t, keep)).toList();
    _tabs
      ..clear()
      ..add(keep);
    _activate(0);
    _retire(removed);
  }

  void closeAll() {
    final removed = List<BrowserTab>.of(_tabs);
    _tabs
      ..clear()
      ..add(BrowserTab());
    _activate(0);
    _retire(removed);
  }

  void _removeAndRetire(List<BrowserTab> ts) {
    for (final t in ts) {
      final i = _tabs.indexOf(t);
      if (i < 0) continue;
      _tabs.removeAt(i);
      if (i < _active) _active--;
    }
    _retire(ts);
  }

  /// Mark closed immediately (late native callbacks become no-ops) and
  /// free native objects only after the widgets have left the tree.
  void _retire(List<BrowserTab> ts) {
    for (final t in ts) {
      t.markClosed();
    }
    _afterFrame(() {
      for (final t in ts) {
        t.dispose();
      }
      if (AppConfig.wipeCookiesWhenLastIncognitoTabCloses &&
          ts.any((t) => t.incognito) &&
          !hasIncognito) {
        CookieManager.instance().deleteAllCookies();
      }
    });
  }

  // -------------------------------------------------- per-tab operations
  Future<void> load(String url, {BrowserTab? tab}) async {
    final t = tab ?? active;
    t.url = url;
    final c = t.controller;
    if (t.live && c != null) {
      await c.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    } // else: initialUrlRequest will use t.url when the view is created
    _notify();
  }

  Future<void> goHome(BrowserTab t) => load(AppConfig.homeUrl, tab: t);

  Future<void> setDesktop(BrowserTab t, bool value) async {
    t.desktop = value;
    _notify();
    final c = t.controller;
    if (c == null) return;
    try {
      // Always send the *full* settings object; a partial one would reset
      // other options to plugin defaults.
      await c.setSettings(settings: t.buildSettings());
      await c.reload();
    } catch (_) {}
    _scheduleSave();
  }

  void openFind(BrowserTab t) => t.findVisible.value = true;

  void closeFind(BrowserTab t) {
    if (t.closed) return;
    t.find?.clearMatches().catchError((_) {});
    t.findResult.value = (0, 0);
    t.findVisible.value = false;
  }

  Future<void> printTab(BrowserTab t) async {
    final c = t.controller;
    if (c == null) return;
    PrintJobController? job;
    try {
      job = await c.printCurrentPage(
          settings: PrintJobSettings(jobName: t.title));
    } catch (_) {
    } finally {
      await job?.dispose(); // PrintJobController owns a method channel
    }
  }

  // ------------------------------------------------------ webview events
  void onWebViewCreated(BrowserTab t, InAppWebViewController c) {
    if (t.closed || !t.live) return;
    t.controller = c;
    if (isActive(t)) _reader.bind(c);
  }

  void onLoadStart(BrowserTab t, WebUri? uri) {
    if (t.closed) return;
    if (uri != null) t.url = uri.toString();
    t.setProgress(0.05);
    if (isActive(t)) _notify();
  }

  void onProgress(BrowserTab t, int p) {
    if (t.closed) return;
    t.setProgress(p / 100);
    if (p >= 100) t.pull?.endRefreshing();
  }

  void onTitle(BrowserTab t, String? title) {
    if (t.closed || title == null || title.isEmpty) return;
    t.title = title;
    if (isActive(t)) _notify();
  }

  Future<void> refreshNav(BrowserTab t) async {
    final c = t.controller;
    if (c == null || t.closed) return;
    try {
      final b = await c.canGoBack();
      final f = await c.canGoForward();
      t.setNav(b, f);
    } catch (_) {}
  }

  Future<void> onUrlChanged(BrowserTab t, WebUri? uri) async {
    if (t.closed) return;
    if (uri != null) t.url = uri.toString();
    await refreshNav(t);
    if (isActive(t)) _notify();
    _scheduleSave();
  }

  Future<void> onLoadStop(BrowserTab t, WebUri? uri) async {
    final c = t.controller;
    if (t.closed || c == null) return;
    if (uri != null) t.url = uri.toString();
    try {
      t.title = (await c.getTitle()) ?? t.title;
      if (t.pendingScrollY > 0) {
        final y = t.pendingScrollY.toInt();
        t.pendingScrollY = 0;
        await c.scrollTo(x: 0, y: y);
      }
    } catch (_) {}
    if (t.closed) return;
    t.setProgress(1);
    await refreshNav(t);
    if (isActive(t)) _notify();
    _scheduleSave();
  }

  /// Android renderer process died (OOM-kill or crash). Without handling
  /// this the whole app is terminated. Rebuild the WebView instead.
  void recover(BrowserTab t) {
    if (t.closed || !t.live) return;
    t.live = false;
    _notify();
    _afterFrame(() {
      if (t.closed) return;
      t.releaseRuntime();
      if (isActive(t)) {
        t.createRuntime();
        _reader.bind(null);
        _notify();
      }
    });
  }

  // ------------------------------------------------ system / lifecycle
  @override
  void didHaveMemoryPressure() {
    if (!_ready) return;
    for (final t in _tabs) {
      if (!isActive(t)) {
        t.thumbnail = null;
        unawaited(_discard(t));
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) unawaited(_saveNow());
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final t in _tabs) {
      t.markClosed();
      t.dispose();
    }
    _tabs.clear();
    super.dispose();
  }
}