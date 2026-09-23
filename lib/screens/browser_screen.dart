import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../core/app_config.dart';
import '../core/utils/url_resolver.dart';
import '../services/keep_awake.dart';
import '../state/chapter_rule_store.dart';
import '../state/library_controller.dart';
import '../state/settings_controller.dart';
import '../state/tabs_controller.dart';
import '../state/element_picker_controller.dart';
import '../state/reader_controller.dart';
import '../widgets/app_drawer.dart';
import '../widgets/chapter_rule_sheet.dart';
import '../widgets/find_bar.dart';
import '../widgets/tab_webview.dart';
import '../widgets/tts_control_bar.dart';
import '../widgets/url_bar.dart';
import 'reader_screen.dart';
import 'tab_switcher_screen.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});
  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen>
    with WidgetsBindingObserver {
  final _urlFocus = FocusNode(debugLabel: 'urlBar');
  late final ReaderController _reader;
  late final ElementPickerController _picker;
  bool _resumed = true, _noticeOpen = false, _sheetOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reader = context.read<ReaderController>()..addListener(_onReader);
    _picker = context.read<ElementPickerController>()..addListener(_onPicker);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => BackgroundSetup.ensureNotificationPermission());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reader.removeListener(_onReader);
    _picker.removeListener(_onPicker);
    _urlFocus.dispose();
    super.dispose();
  }

  void _onReader() {
    final n = _reader.notice;
    if (n == null || !_resumed || _noticeOpen || !mounted) return;
    _noticeOpen = true;
    _reader.clearNotice();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _noticeOpen = false;
        return;
      }
      final fix = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.stop_circle_outlined),
          title: const Text('Auto-read stopped'),
          content: Text(n.message),
          actions: [
            if (n.canFix)
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Set button again')),
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
      _noticeOpen = false;
      if (fix == true && mounted) {
        _picker.start(context.read<TabsController>().active);
      }
    });
  }

  void _onPicker() {
    if (_picker.picked == null || _sheetOpen || !mounted) return;
    _sheetOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _sheetOpen = false;
        return;
      }
      await showChapterRuleSheet(context,
          picker: _picker, rules: context.read<ChapterRuleStore>());
      _sheetOpen = false;
    });
  }

  Future<void> _openSwitcher(BuildContext context, TabsController tabs) async {
    _urlFocus.unfocus();
    final t = tabs.active;
    try {
      // Small low-quality JPEG: ~15-30 KB. Only the active tab is captured.
      t.thumbnail = await t.controller?.takeScreenshot(
        screenshotConfiguration: ScreenshotConfiguration(
            compressFormat: CompressFormat.JPEG,
            quality: 40,
            snapshotWidth: 300),
      );
    } catch (_) {}
    if (!context.mounted) return;
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const TabSwitcherScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final tabs = context.watch<TabsController>();
    if (!tabs.ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final tab = tabs.active;
    final library = context.read<LibraryController>();
    final engine = context.read<SettingsController>().settings.searchEngine;
    final cs = Theme.of(context).colorScheme;
    final picker = context.watch<ElementPickerController>();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;

        // 1. URL bar active -> just drop focus (hides suggestions + reverts).
        if (_urlFocus.hasFocus) return _urlFocus.unfocus();
        if (tab.findVisible.value) return tabs.closeFind(tab);
        if (await tab.controller?.canGoBack() ?? false) {
          return tab.controller!.goBack();
        }
        if (tabs.count > 1) return tabs.closeTab(tab.id);
        SystemNavigator.pop();
      },
      child: Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          titleSpacing: 0,
          leading: Builder(
            builder: (c) => IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(c).openDrawer()),
          ),
          title: UrlBar(
            key: ValueKey('url-${tab.id}'),
            url: tab.url,
            incognito: tab.incognito,
            suggest: library.suggest,
            recent: library.recent,
            focusNode: _urlFocus,
            onSubmit: (v) =>
                tabs.load(UrlResolver.resolve(v, engine, AppConfig.homeUrl)),
          ),
          actions: [
            _TabCountButton(
                count: tabs.count, onTap: () => _openSwitcher(context, tabs)),
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'new':
                    tabs.newTab();
                  case 'new_incognito':
                    tabs.newTab(incognito: true);
                  case 'bookmark':
                    if (tab.url.isEmpty || tab.url.startsWith('about:')) return;
                    final added =
                        await library.toggleBookmark(tab.url, tab.title);
                    tab.setBookmarked(added);
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content:
                            Text(added ? 'Bookmark added' : 'Bookmark removed'),
                        duration: const Duration(seconds: 1)));
                  case 'find':
                    tabs.openFind(tab);
                  case 'desktop':
                    await tabs.setDesktop(tab, !tab.desktop);
                  case 'duplicate':
                    tabs.duplicate(tab.id);
                  case 'print':
                    await tabs.printTab(tab);
                  case 'close_others':
                    tabs.closeOthers(tab.id);
                  case 'close':
                    tabs.closeTab(tab.id);
                  case 'home':
                    await tabs.goHome(tab);
                  case 'reload':
                    await tab.controller?.reload();
                  case 'reader':
                    if (!context.mounted) return;
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ReaderScreen()));
                  case 'set_next':
                    context.read<ElementPickerController>().start(tab);
                  case 'next_chapter':
                    context.read<ReaderController>().nextChapter();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'new', child: _Item(Icons.add, 'New tab')),
                const PopupMenuItem(
                    value: 'new_incognito',
                    child: _Item(Icons.visibility_off, 'New incognito tab')),
                const PopupMenuDivider(),
                PopupMenuItem(
                    value: 'bookmark',
                    child: _Item(
                        tab.bookmarked.value ? Icons.star : Icons.star_border,
                        tab.bookmarked.value
                            ? 'Remove bookmark'
                            : 'Add bookmark')),
                const PopupMenuItem(
                    value: 'find', child: _Item(Icons.search, 'Find on page')),
                CheckedPopupMenuItem(
                    value: 'desktop',
                    checked: tab.desktop,
                    child: const Text('Desktop site')),
                const PopupMenuItem(
                    value: 'duplicate',
                    child: _Item(Icons.copy, 'Duplicate tab')),
                const PopupMenuItem(
                    value: 'print', child: _Item(Icons.print, 'Print')),
                const PopupMenuItem(
                    value: 'reader',
                    child: _Item(Icons.chrome_reader_mode, 'Reader view')),
                const PopupMenuDivider(),
                const PopupMenuItem(
                    value: 'home', child: _Item(Icons.home, 'Home')),
                const PopupMenuItem(
                    value: 'reload', child: _Item(Icons.refresh, 'Reload')),
                const PopupMenuItem(
                    value: 'reread',
                    child: _Item(Icons.sync, 'Re-read page content')),
                const PopupMenuItem(
                    value: 'close_others',
                    child: _Item(Icons.tab_unselected, 'Close other tabs')),
                const PopupMenuItem(
                    value: 'close', child: _Item(Icons.close, 'Close tab')),
                const PopupMenuItem(
                    value: 'set_next',
                    child: _Item(Icons.ads_click, 'Set next-chapter button')),
                const PopupMenuItem(
                    value: 'next_chapter',
                    child: _Item(
                        Icons.keyboard_double_arrow_right, 'Next chapter now')),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: ValueListenableBuilder<double>(
              valueListenable: tab.progress,
              builder: (_, p, __) => (p > 0 && p < 1)
                  ? LinearProgressIndicator(value: p, minHeight: 2)
                  : const SizedBox(height: 2),
            ),
          ),
        ),
        body: Column(
          children: [
            if (tab.incognito)
              Container(
                width: double.infinity,
                color: cs.inverseSurface,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('Incognito tab: history is not saved',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onInverseSurface, fontSize: 12)),
              ),
            if (picker.active && picker.picked == null)
              Material(
                color: cs.primaryContainer,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(children: [
                    Icon(Icons.touch_app,
                        size: 18, color: cs.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Tap the "Next chapter" button on the page',
                          style: TextStyle(color: cs.onPrimaryContainer)),
                    ),
                    TextButton(
                        onPressed: picker.stop, child: const Text('Cancel')),
                  ]),
                ),
              ),
            ValueListenableBuilder<bool>(
              valueListenable: tab.findVisible,
              builder: (_, v, __) => v
                  ? FindBar(key: ValueKey('find-${tab.id}'), tab: tab)
                  : const SizedBox.shrink(),
            ),
            Expanded(child: _TabStack(tabs: tabs)),
            ValueListenableBuilder<bool>(
              valueListenable: tab.canBack,
              builder: (_, back, __) => ValueListenableBuilder<bool>(
                valueListenable: tab.canForward,
                builder: (_, fwd, __) => TtsControlBar(
                  canGoBack: back,
                  canGoForward: fwd,
                  onWebBack: () => tab.controller?.goBack(),
                  onWebForward: () => tab.controller?.goForward(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Only LIVE tabs are mounted. Keyed children keep their WebView state when
/// the list changes; discarded tabs simply aren't in the list.
class _TabStack extends StatelessWidget {
  const _TabStack({required this.tabs});
  final TabsController tabs;

  @override
  Widget build(BuildContext context) {
    final live = tabs.liveTabs;
    final idx = live.indexWhere((t) => identical(t, tabs.active));
    return IndexedStack(
      index: idx < 0 ? 0 : idx,
      children: [for (final t in live) TabWebView(key: ValueKey(t.id), tab: t)],
    );
  }
}

class _TabCountButton extends StatelessWidget {
  const _TabCountButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: 'Tabs',
      onPressed: onTap,
      icon: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: cs.onSurface, width: 2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(count > 99 ? ':D' : '$count',
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: cs.onSurface)),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  const _Item(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
      ]);
}
