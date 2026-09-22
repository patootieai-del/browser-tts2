import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/browser_tab.dart';
import '../state/library_controller.dart';
import '../state/reader_controller.dart';
import '../state/settings_controller.dart';
import '../state/tabs_controller.dart';

class TabWebView extends StatelessWidget {
  const TabWebView({super.key, required this.tab});
  final BrowserTab tab;

  @override
  Widget build(BuildContext context) {
    // Capture objects (not BuildContext) so callbacks are safe after unmount.
    final tabs = context.read<TabsController>();
    final reader = context.read<ReaderController>();
    final library = context.read<LibraryController>();
    final settings = context.read<SettingsController>();

    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(tab.url)),
      initialSettings: tab.buildSettings(),
      pullToRefreshController: tab.pull,
      findInteractionController: tab.find,
      onWebViewCreated: (c) => tabs.onWebViewCreated(tab, c),
      onLoadStart: (c, uri) => tabs.onLoadStart(tab, uri),
      onProgressChanged: (c, p) => tabs.onProgress(tab, p),
      onTitleChanged: (c, t) => tabs.onTitle(tab, t),
      onUpdateVisitedHistory: (c, uri, _) => tabs.onUrlChanged(tab, uri),
      onLoadStop: (c, uri) async {
        await tabs.onLoadStop(tab, uri);
        if (tab.closed) return;

        if (!tab.incognito) {
          unawaited(library.recordVisit(tab.url, tab.title));
        }
        library.isBookmarked(tab.url).then(tab.setBookmarked).catchError((_) {});

        // Only the visible tab feeds the reader.
        if (tabs.isActive(tab)) {
          await reader.loadPage(autoPlay: settings.settings.autoReadOnLoad);
        }
      },
      onRenderProcessGone: (c, detail) => tabs.recover(tab),
      shouldOverrideUrlLoading: (c, action) async {
        final u = action.request.url;
        if (u == null) return NavigationActionPolicy.ALLOW;
        const web = ['http', 'https', 'about', 'data', 'blob', 'javascript'];
        if (web.contains(u.scheme)) return NavigationActionPolicy.ALLOW;
        if (['mailto', 'tel', 'sms'].contains(u.scheme)) {
          try {
            await launchUrl(u.uriValue, mode: LaunchMode.externalApplication);
          } catch (_) {}
        }
        return NavigationActionPolicy.CANCEL; // incl. intent:// (unsafe)
      },
      onDownloadStartRequest: (c, req) async {
        try {
          await launchUrl(req.url.uriValue,
              mode: LaunchMode.externalApplication);
        } catch (_) {}
      },
      // Deny camera/mic/etc. by default.
      onPermissionRequest: (c, req) async => PermissionResponse(
          resources: req.resources, action: PermissionResponseAction.DENY),
    );
  }
}