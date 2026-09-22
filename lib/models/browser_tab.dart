import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/app_config.dart';

/// One browser tab. Holds persistent data (url/title/...) plus *runtime*
/// objects that exist only while the tab is "live".
///
/// LIFECYCLE
///   createRuntime()  -> live = true   (widget mounted, controllers created)
///   live = false     -> widget removed from tree
///   releaseRuntime() -> native helper objects disposed (post-frame)
///   dispose()        -> tab closed for good, notifiers disposed
class BrowserTab {
  static int _seq = 0;

  BrowserTab({
    String? id,
    String? url,
    this.title = 'New tab',
    this.incognito = false,
    this.desktop = false,
  })  : id = id ?? '${DateTime.now().microsecondsSinceEpoch}-${_seq++}',
        url = url ?? AppConfig.homeUrl;

  // ---- persistent ----
  final String id;
  String url;
  String title;
  final bool incognito;
  bool desktop;
  double pendingScrollY = 0;
  DateTime lastActive = DateTime.now();
  Uint8List? thumbnail; // small JPEG, only captured for the switcher

  // ---- runtime ----
  bool live = false;
  bool closed = false;
  InAppWebViewController? controller;
  PullToRefreshController? pull;
  FindInteractionController? find;

  final ValueNotifier<double> progress = ValueNotifier(0);
  final ValueNotifier<bool> canBack = ValueNotifier(false);
  final ValueNotifier<bool> canForward = ValueNotifier(false);
  final ValueNotifier<bool> findVisible = ValueNotifier(false);
  final ValueNotifier<(int, int)> findResult = ValueNotifier((0, 0));
  final ValueNotifier<bool> bookmarked = ValueNotifier(false);

  // Guarded setters: native callbacks can arrive after a tab is closed.
  void setProgress(double v) { if (!closed) progress.value = v; }
  void setNav(bool b, bool f) {
    if (closed) return;
    canBack.value = b;
    canForward.value = f;
  }
  void setBookmarked(bool v) { if (!closed) bookmarked.value = v; }

  InAppWebViewSettings buildSettings() => InAppWebViewSettings(
        // NOTE: deliberately NOT using `incognito: true`, see design notes.
        cacheEnabled: !incognito,
        thirdPartyCookiesEnabled: !incognito,
        javaScriptEnabled: true,
        useShouldOverrideUrlLoading: true,
        mediaPlaybackRequiresUserGesture: true,
        transparentBackground: true,
        supportZoom: true,
        builtInZoomControls: true,
        displayZoomControls: false,
        useHybridComposition: true,
        safeBrowsingEnabled: true,
        supportMultipleWindows: false, // target=_blank opens in same view
        preferredContentMode: desktop
            ? UserPreferredContentMode.DESKTOP
            : UserPreferredContentMode.RECOMMENDED,
      );

  void createRuntime() {
    _releaseObjects(); // in case a release is still pending
    pull = PullToRefreshController(
      onRefresh: () async {
        await controller?.reload();
      },
    );
    find = FindInteractionController(
      onFindResultReceived: (c, active, total, done) {
        if (!closed) findResult.value = (active, total);
      },
    );
    live = true;
  }

  /// Called post-frame after the widget left the tree.
  void releaseRuntime() {
    if (live) return; // re-activated before the release ran
    _releaseObjects();
  }

  void _releaseObjects() {
    pull?.dispose();
    find?.dispose();
    pull = null;
    find = null;
    controller = null; // drop the ref to the (dead) WebView controller
    if (!closed) findVisible.value = false;
  }

  void markClosed() {
    closed = true;
    live = false;
  }

  void dispose() {
    _releaseObjects();
    thumbnail = null;
    progress.dispose();
    canBack.dispose();
    canForward.dispose();
    findVisible.dispose();
    findResult.dispose();
    bookmarked.dispose();
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'url': url,
        'title': title,
        'desktop': desktop,
        'scroll': pendingScrollY,
      };

  factory BrowserTab.fromJson(Map<String, dynamic> j) => BrowserTab(
        id: j['id'] as String?,
        url: j['url'] as String?,
        title: (j['title'] as String?) ?? 'New tab',
        desktop: (j['desktop'] as bool?) ?? false,
      )..pendingScrollY = ((j['scroll'] as num?) ?? 0).toDouble();
}