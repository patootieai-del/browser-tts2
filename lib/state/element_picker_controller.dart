import 'package:flutter/foundation.dart';

import '../models/browser_tab.dart';
import '../services/page_scripts.dart';

class PickedElement {
  const PickedElement({
    required this.selector,
    required this.label,
    required this.tag,
    required this.href,
    required this.url,
    required this.canGoUp,
  });

  final String selector, label, tag, href, url;
  final bool canGoUp;

  factory PickedElement.fromMap(Map<String, dynamic> m) => PickedElement(
        selector: '${m['selector'] ?? ''}',
        label: '${m['label'] ?? ''}',
        tag: '${m['tag'] ?? ''}',
        href: '${m['href'] ?? ''}',
        url: '${m['url'] ?? ''}',
        canGoUp: m['canGoUp'] == true,
      );
}

class ElementPickerController extends ChangeNotifier {
  BrowserTab? _tab;
  PickedElement? _picked;
  bool _active = false;

  bool get active => _active;
  PickedElement? get picked => _picked;

  Future<void> start(BrowserTab tab) async {
    final c = tab.controller;
    if (c == null) return;
    _tab = tab;
    _picked = null;
    _active = true;
    notifyListeners();
    try {
      await c.evaluateJavascript(source: PageScripts.picker);
    } catch (_) {
      _reset();
    }
  }

  void onPicked(String tabId, Map<String, dynamic> m) {
    if (!_active || _tab?.id != tabId) return;
    _picked = PickedElement.fromMap(m);
    notifyListeners();
  }

  /// Select the parent of the current element (when an inner span was tapped).
  Future<void> up() async {
    try {
      await _tab?.controller?.evaluateJavascript(
          source: 'window.__voxPicker && window.__voxPicker.up();');
    } catch (_) {}
  }

  Future<void> stop() async {
    final t = _tab;
    _reset();
    try {
      await t?.controller?.evaluateJavascript(
          source: 'window.__voxPicker && window.__voxPicker.stop();');
    } catch (_) {}
  }

  /// The page navigated: the injected picker is gone.
  void onNavigation(String tabId) {
    if (_active && _tab?.id == tabId) _reset();
  }

  void _reset() {
    _active = false;
    _picked = null;
    _tab = null;
    notifyListeners();
  }
}