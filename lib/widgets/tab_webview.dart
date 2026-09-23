import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/browser_tab.dart';
import '../services/page_scripts.dart';
import '../state/library_controller.dart';
import '../state/reader_controller.dart';
import '../state/settings_controller.dart';
import '../state/tabs_controller.dart';
import '../state/element_picker_controller.dart';

class TabWebView extends StatelessWidget {
  const TabWebView({super.key, required this.tab});
  final BrowserTab tab;

  @override
  Widget build(BuildContext context) {
    final tabs = context.read<TabsController>();
    final reader = context.read<ReaderController>();
    final library = context.read<LibraryController>();
    final settings = context.read<SettingsController>();
    final picker = context.read<ElementPickerController>();

    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri(tab.url)),
      initialSettings: tab.buildSettings(),
      initialUserScripts: UnmodifiableListView<UserScript>([
        UserScript(
          source: PageScripts.contentWatcher,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_END,
          forMainFrameOnly: true,
        ),
      ]),
      pullToRefreshController: tab.pull,
      findInteractionController: tab.find,
      onWebViewCreated: (c) {
        tabs.onWebViewCreated(tab, c);
        c.addJavaScriptHandler(
          handlerName: 'voxContentChanged',
          callback: (args) {
            if (tab.closed || !tabs.isActive(tab)) return;
            final len = (args.length > 1 && args[1] is num)
                ? (args[1] as num).toInt()
                : 0;
            reader.onContentChanged(len);
          },
        );
        c.addJavaScriptHandler(
          handlerName: 'voxElementPicked',
          callback: (args) {
            if (tab.closed || args.isEmpty || args.first is! Map) return;
            picker.onPicked(
                tab.id, Map<String, dynamic>.from(args.first as Map));
          },
        );
      },
      onLoadStart: (c, uri) {
        tabs.onLoadStart(tab, uri);
        if (tabs.isActive(tab)) {
          reader
              .onNavigationStarted(); // lets an in-flight chapter advance know
          picker.onNavigation(tab.id);
        }
      },
      onProgressChanged: (c, p) => tabs.onProgress(tab, p),
      onTitleChanged: (c, t) => tabs.onTitle(tab, t),
      onUpdateVisitedHistory: (c, uri, _) async {
        await tabs.onUrlChanged(tab, uri);
        if (tab.closed || uri == null) return;
        // progress >= 1 => not a normal page load, i.e. a SPA route change.
        if (tabs.isActive(tab) && tab.progress.value >= 1) {
          reader.onRouteChanged(uri.toString(),
              autoPlay: settings.settings.autoReadOnLoad);
        }
      },
      onLoadStop: (c, uri) async {
        await tabs.onLoadStop(tab, uri);
        if (tab.closed) return;

        if (!tab.incognito) {
          unawaited(library.recordVisit(tab.url, tab.title));
        }
        library
            .isBookmarked(tab.url)
            .then(tab.setBookmarked)
            .catchError((_) {});

        if (tabs.isActive(tab)) {
          await reader.loadPage(
              autoPlay: settings.settings.autoReadOnLoad, url: tab.url);
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
        return NavigationActionPolicy.CANCEL;
      },
      onDownloadStartRequest: (c, req) async {
        try {
          await launchUrl(req.url.uriValue,
              mode: LaunchMode.externalApplication);
        } catch (_) {}
      },
      onPermissionRequest: (c, req) async => PermissionResponse(
          resources: req.resources, action: PermissionResponseAction.DENY),
    );
  }
}
