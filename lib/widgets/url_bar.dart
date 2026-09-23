import 'package:flutter/material.dart';

import '../core/utils/url_suggestions.dart';

class UrlBar extends StatefulWidget {
  const UrlBar({
    super.key,
    required this.url,
    required this.incognito,
    required this.onSubmit,
    this.suggest,
    this.focusNode,
  });

  final String url;
  final bool incognito;
  final ValueChanged<String> onSubmit;
  final Future<List<UrlSuggestion>> Function(String query)? suggest;

  /// Supply one if the host needs to unfocus the bar (e.g. the back button).
  final FocusNode? focusNode;

  @override
  State<UrlBar> createState() => _UrlBarState();
}

class _UrlBarState extends State<UrlBar> {
  final _ctrl = TextEditingController();
  final _fieldKey = GlobalKey();
  FocusNode? _ownedFocus;
  late FocusNode _focus;

  bool _editing = false;
  bool _hadFocusOnPointerDown = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? (_ownedFocus = FocusNode());
    _ctrl.text = widget.url;
    _focus.addListener(_onFocusChanged);
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

  void _onFocusChanged() {
    final has = _focus.hasFocus;
    if (has) {
      _submitted = false;
      _ctrl.text = widget.url; // edit the full, current URL
      _selectAllSoon();
    } else if (!_submitted) {
      // Focus lost without submitting: discard the edit. This also empties
      // optionsBuilder, so the suggestion overlay can't linger.
      _ctrl.text = widget.url;
    }
    if (_editing != has && mounted) setState(() => _editing = has);
  }

  void _selectAll() {
    if (!mounted || !_focus.hasFocus) return;
    _ctrl.selection =
        TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
  }

  void _selectAllSoon() =>
      WidgetsBinding.instance.addPostFrameCallback((_) => _selectAll());

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _ownedFocus?.dispose(); // never dispose a node we don't own
    _ctrl.dispose();
    super.dispose();
  }

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

  /// Width of the field, so the overlay lines up exactly.
  double? get _fieldWidth {
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    return (box != null && box.attached && box.hasSize) ? box.size.width : null;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return RawAutocomplete<UrlSuggestion>(
      textEditingController: _ctrl,
      focusNode: _focus,
      displayStringForOption: (s) => s.url,
      optionsBuilder: (value) async {
        final q = value.text.trim();
        if (widget.suggest == null ||
            !_focus.hasFocus || // no focus => no suggestions
            q.isEmpty ||
            value.text == widget.url) {
          return const <UrlSuggestion>[];
        }
        final r = await widget.suggest!(q);
        // Focus may have been lost while the query ran.
        return _focus.hasFocus ? r : const <UrlSuggestion>[];
      },
      onSelected: (s) => _go(s.url),
      optionsViewBuilder: (context, onSelected, options) => _SuggestionList(
        options: options,
        onSelected: onSelected,
        onFill: _fill,
        width: _fieldWidth, // aligned to the field
      ),
      fieldViewBuilder: (context, ctrl, focus, _) {
        // We deliberately ignore the provided onFieldSubmitted: it would pick
        // the highlighted suggestion instead of what the user typed.
        return Listener(
          key: _fieldKey,
          onPointerDown: (_) => _hadFocusOnPointerDown = focus.hasFocus,
          child: TextField(
            controller: ctrl,
            focusNode: focus,
            textInputAction: TextInputAction.go,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            // Tapping anywhere else in the app drops focus (and with it the
            // suggestions). Taps inside the options list are excluded by the
            // TextFieldTapRegion that RawAutocomplete puts around them.
            onTapOutside: (_) {
              if (focus.hasFocus) focus.unfocus();
            },
            onTap: () {
              if (!_hadFocusOnPointerDown) {
                _selectAll();
                _selectAllSoon();
              }
            },
            onSubmitted: _go,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search or type a URL',
              prefixIcon: Icon(
                widget.incognito
                    ? Icons.visibility_off
                    : (widget.url.startsWith('https')
                        ? Icons.lock
                        : Icons.public),
                size: 18,
                color: cs.onSurfaceVariant,
              ),
              suffixIcon: _editing
                  ? ValueListenableBuilder<TextEditingValue>(
                      valueListenable: ctrl,
                      builder: (_, v, __) => v.text.isEmpty
                          ? const SizedBox.shrink()
                          : IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: ctrl.clear,
                            ),
                    )
                  : null,
            ),
            style: TextStyle(fontSize: 14, color: cs.onSurface),
          ),
        );
      },
    );
  }
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({
    required this.options,
    required this.onSelected,
    required this.onFill,
    required this.width,
  });

  final Iterable<UrlSuggestion> options;
  final AutocompleteOnSelected<UrlSuggestion> onSelected;
  final ValueChanged<UrlSuggestion> onFill;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = options.toList(growable: false);

    // The follower already puts our top-left at the field's bottom-left, so
    // matching the field width is all the alignment we need.
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Material(
          elevation: 6,
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: width,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final s = list[i];
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(
                      s.isBookmark ? Icons.star : Icons.history,
                      size: 20,
                      color: s.isBookmark ? Colors.amber : cs.onSurfaceVariant,
                    ),
                    title: Text(s.title.isEmpty ? s.display : s.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(s.display,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      tooltip: 'Edit this address',
                      icon: const Icon(Icons.north_west, size: 18),
                      onPressed: () => onFill(s),
                    ),
                    onTap: () => onSelected(s),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
