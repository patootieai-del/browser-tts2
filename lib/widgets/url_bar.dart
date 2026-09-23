import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/utils/url_suggestions.dart';
import 'package:flutter/foundation.dart' show ValueListenable;

class UrlBar extends StatefulWidget {
  const UrlBar({
    super.key,
    required this.url,
    required this.incognito,
    required this.onSubmit,
    this.suggest,
    this.recent,
    this.focusNode,
    this.onCopy,
    this.onShare,
  });

  final String url;
  final bool incognito;
  final ValueChanged<String> onSubmit;

  /// Suggestions for typed text.
  final Future<List<UrlSuggestion>> Function(String query)? suggest;

  /// Most recent history, shown while the bar is empty.
  final Future<List<UrlSuggestion>> Function()? recent;

  /// Supply one if the host needs to unfocus the bar (e.g. back button).
  final FocusNode? focusNode;

  /// Overrides (mainly for tests). Defaults: clipboard + snackbar, share sheet.
  final Future<void> Function(String url)? onCopy;
  final Future<void> Function(String url)? onShare;

  @override
  State<UrlBar> createState() => _UrlBarState();
}

class _Results {
  const _Results(this.items, {this.recent = false});
  final List<UrlSuggestion> items;
  final bool recent;
}

class _UrlBarState extends State<UrlBar> {
  static const double _phoneBreakpoint = 600; // shortest side, dp

  final _ctrl = TextEditingController();
  final _fieldKey = GlobalKey();
  final _link = LayerLink();
  final _overlay = OverlayPortalController();
  final _results = ValueNotifier<_Results>(const _Results([]));

  FocusNode? _ownedFocus;
  late FocusNode _focus;

  bool _editing = false;
  bool _submitted = false;
  int _queryToken = 0;
  String? _lastQuery;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? (_ownedFocus = FocusNode());
    _ctrl.text = widget.url;
    _focus.addListener(_onFocusChanged);
    _ctrl.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant UrlBar old) {
    super.didUpdateWidget(old);
    if (widget.focusNode != old.focusNode) {
      _focus.removeListener(_onFocusChanged);
      _ownedFocus?.dispose();
      _ownedFocus = null;
      _focus = widget.focusNode ?? (_ownedFocus = FocusNode());
      _focus.addListener(_onFocusChanged);
    }
    if (widget.url != old.url) {
      _submitted = false;
      if (!_editing) _ctrl.text = widget.url;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _ctrl.removeListener(_onTextChanged);
    _ownedFocus?.dispose(); // never dispose a node we don't own
    _ctrl.dispose();
    _results.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- focus
  void _onFocusChanged() {
    final has = _focus.hasFocus;
    if (has) {
      _submitted = false;
      _lastQuery = null;
      _ctrl.clear(); // activating the bar clears it
      if (!_overlay.isShowing) _overlay.show();
      _refresh(); // no-op if clear() already triggered it
    } else {
      _queryToken++; // drop in-flight queries
      if (_overlay.isShowing) _overlay.hide();
      _results.value = const _Results([]);
      if (!_submitted) _ctrl.text = widget.url; // revert unsubmitted edits
    }
    if (_editing != has && mounted) setState(() => _editing = has);
  }

  void _onTextChanged() {
    if (_focus.hasFocus) _refresh();
  }

  // ------------------------------------------------------- suggestions
  Future<void> _refresh() async {
    final raw = _ctrl.text;
    if (raw == _lastQuery) return; // e.g. caret moves
    _lastQuery = raw;
    final token = ++_queryToken;
    final q = raw.trim();

    var items = const <UrlSuggestion>[];
    try {
      if (q.isEmpty) {
        final r = await (widget.recent?.call() ??
            Future.value(const <UrlSuggestion>[]));
        final current = UrlRanker.key(widget.url);
        items = r.where((s) => UrlRanker.key(s.url) != current).toList();
      } else if (raw != widget.url && widget.suggest != null) {
        items = await widget.suggest!(q);
      }
    } catch (_) {
      items = const [];
    }
    if (!mounted || token != _queryToken || !_focus.hasFocus) return;
    _results.value = _Results(items, recent: q.isEmpty);
  }

  // ----------------------------------------------------------- actions
  void _go(String text) {
    _submitted = true;
    _focus.unfocus();
    widget.onSubmit(text);
  }

  void _fill(UrlSuggestion s) {
    _ctrl.value = TextEditingValue(
      text: s.url,
      selection: TextSelection.collapsed(offset: s.url.length),
    );
  }

  /// Current URL into the field, caret at the very end.
  void _edit() {
    final u = widget.url;
    _ctrl.value = TextEditingValue(
      text: u,
      selection: TextSelection.collapsed(offset: u.length),
    );
    _focus.requestFocus();
  }

  Future<void> _copy() async {
    final url = widget.url;
    final messenger = ScaffoldMessenger.maybeOf(context);
    _focus.unfocus(); // the panel would hide the snackbar on phones
    if (widget.onCopy != null) {
      await widget.onCopy!(url);
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    messenger?.showSnackBar(const SnackBar(
        content: Text('Address copied'), duration: Duration(seconds: 1)));
  }

  Future<void> _share() async {
    final url = widget.url;
    _focus.unfocus();
    if (widget.onShare != null) {
      await widget.onShare!(url);
    } else {
      await Share.share(url);
    }
  }

  // ----------------------------------------------------------- overlay
  Widget _buildOverlay(BuildContext context) {
    final field = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (field == null || !field.attached || !field.hasSize) {
      return const SizedBox.shrink();
    }
    final media = MediaQuery.of(context);
    final compact = media.size.shortestSide < _phoneBreakpoint;

    Widget panel({required double? maxHeight}) => TextFieldTapRegion(
          // Taps inside the panel must not count as "outside the field".
          child: ExcludeFocus(
            child: _SuggestionPanel(
              compact: compact,
              maxHeight: maxHeight,
              url: widget.url,
              incognito: widget.incognito,
              results: _results,
              onEdit: _edit,
              onCopy: _copy,
              onShare: _share,
              onSelect: (s) => _go(s.url),
              onFill: _fill,
            ),
          ),
        );

    if (compact) {
      // Full page: from just under the field to the top of the keyboard.
      final overlayBox =
          Overlay.of(context).context.findRenderObject() as RenderBox;
      final fieldBottom = field
          .localToGlobal(Offset(0, field.size.height), ancestor: overlayBox)
          .dy;
      return Stack(children: [
        Positioned(
          left: 0,
          right: 0,
          top: fieldBottom + 8,
          bottom: media.viewInsets.bottom,
          child: panel(maxHeight: null),
        ),
      ]);
    }

    // Tablet: dropdown with the field's x-position and width.
    final fieldBottom = field.localToGlobal(Offset(0, field.size.height)).dy;
    final available =
        media.size.height - media.viewInsets.bottom - fieldBottom - 16;
    final maxH = math.max(160.0, math.min(480.0, available));
    return CompositedTransformFollower(
      link: _link,
      showWhenUnlinked: false,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      offset: const Offset(0, 4),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: field.size.width, child: panel(maxHeight: maxH)),
      ),
    );
  }

  // -------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _overlay,
        overlayChildBuilder: _buildOverlay,
        child: TextField(
          key: _fieldKey,
          controller: _ctrl,
          focusNode: _focus,
          textInputAction: TextInputAction.go,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          // Tap anywhere else -> unfocus (panel taps are excluded above).
          onTapOutside: (_) {
            if (_focus.hasFocus) _focus.unfocus();
          },
          // Enter submits what was typed, never a hidden "top suggestion".
          onSubmitted: _go,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search or type a URL',
            prefixIcon: Icon(
              _pageIcon(widget.url, widget.incognito),
              size: 18,
              color: cs.onSurfaceVariant,
            ),
            suffixIcon: _editing
                ? ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _ctrl,
                    builder: (_, v, __) => v.text.isEmpty
                        ? const SizedBox.shrink()
                        : IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: _ctrl.clear,
                          ),
                  )
                : null,
          ),
          style: TextStyle(fontSize: 14, color: cs.onSurface),
        ),
      ),
    );
  }
}

IconData _pageIcon(String url, bool incognito) => incognito
    ? Icons.visibility_off
    : (url.startsWith('https') ? Icons.lock : Icons.public);

// =====================================================================

class _SuggestionPanel extends StatelessWidget {
  const _SuggestionPanel({
    required this.compact,
    required this.maxHeight,
    required this.url,
    required this.incognito,
    required this.results,
    required this.onEdit,
    required this.onCopy,
    required this.onShare,
    required this.onSelect,
    required this.onFill,
  });

  final bool compact;
  final double? maxHeight;
  final String url;
  final bool incognito;
  final ValueListenable<_Results> results;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final ValueChanged<UrlSuggestion> onSelect;
  final ValueChanged<UrlSuggestion> onFill;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final header = _CurrentUrlHeader(
      url: url,
      incognito: incognito,
      onEdit: onEdit,
      onCopy: onCopy,
      onShare: onShare,
    );

    final list = ValueListenableBuilder<_Results>(
      valueListenable: results,
      builder: (_, r, __) {
        if (r.items.isEmpty) {
          return compact
              ? Center(
                  child: Text(r.recent ? 'No history yet' : 'No suggestions',
                      style: TextStyle(color: cs.onSurfaceVariant)))
              : const SizedBox.shrink();
        }
        return ListView.builder(
          padding: EdgeInsets.zero,
          shrinkWrap: !compact,
          itemCount: r.items.length + (r.recent ? 1 : 0),
          itemBuilder: (_, i) {
            if (r.recent && i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('Recent',
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: cs.primary)),
              );
            }
            final s = r.items[i - (r.recent ? 1 : 0)];
            return ListTile(
              dense: true,
              leading: Icon(
                s.isBookmark ? Icons.star : Icons.history,
                size: 20,
                color: s.isBookmark ? Colors.amber : cs.onSurfaceVariant,
              ),
              title: Text(s.title.isEmpty ? s.display : s.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle:
                  Text(s.display, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: IconButton(
                tooltip: 'Edit this address',
                icon: const Icon(Icons.north_west, size: 18),
                onPressed: () => onFill(s),
              ),
              onTap: () => onSelect(s),
            );
          },
        );
      },
    );

    if (compact) {
      return Material(
        key: const Key('urlSuggestionPanel'),
        color: cs.surface,
        child: Column(children: [
          header,
          const Divider(height: 1),
          Expanded(child: list),
        ]),
      );
    }

    return Material(
      key: const Key('urlSuggestionPanel'),
      elevation: 6,
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight ?? 480),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          header,
          const Divider(height: 1),
          Flexible(child: list),
        ]),
      ),
    );
  }
}

class _CurrentUrlHeader extends StatelessWidget {
  const _CurrentUrlHeader({
    required this.url,
    required this.incognito,
    required this.onEdit,
    required this.onCopy,
    required this.onShare,
  });

  final String url;
  final bool incognito;
  final VoidCallback onEdit;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final has = url.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      child: Row(children: [
        Icon(_pageIcon(url, incognito), size: 20, color: cs.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Text(has ? url : 'New tab',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium),
        ),
        IconButton(
            tooltip: 'Edit address',
            icon: const Icon(Icons.edit, size: 20),
            onPressed: has ? onEdit : null),
        IconButton(
            tooltip: 'Copy address',
            icon: const Icon(Icons.content_copy, size: 20),
            onPressed: has ? onCopy : null),
        IconButton(
            tooltip: 'Share address',
            icon: const Icon(Icons.share, size: 20),
            onPressed: has ? onShare : null),
      ]),
    );
  }
}
