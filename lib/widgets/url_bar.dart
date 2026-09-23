import 'package:flutter/material.dart';

import '../core/utils/url_suggestions.dart';

class UrlBar extends StatefulWidget {
  const UrlBar({
    super.key,
    required this.url,
    required this.incognito,
    required this.onSubmit,
    this.suggest,
  });

  final String url;
  final bool incognito;
  final ValueChanged<String> onSubmit;
  final Future<List<UrlSuggestion>> Function(String query)? suggest;

  @override
  State<UrlBar> createState() => _UrlBarState();
}

class _UrlBarState extends State<UrlBar> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  final _fieldKey = GlobalKey();
  bool _editing = false;
  bool _hadFocusOnPointerDown = false;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    _ctrl.text = widget.url;
    _focus.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    final has = _focus.hasFocus;
    if (has) {
      _submitted = false;
      _ctrl.text = widget.url;
      _selectAllSoon();
    } else if (!_submitted) {
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
  void didUpdateWidget(covariant UrlBar old) {
    super.didUpdateWidget(old);
    if (widget.url != old.url) {
      _submitted = false;
      if (!_editing) _ctrl.text = widget.url;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _go(String text) {
    _submitted = true;
    _focus.unfocus();
    widget.onSubmit(text);
  }

  /// Copy a suggestion into the field for editing (does not navigate).
  void _fill(UrlSuggestion s) {
    _ctrl.value = TextEditingValue(
      text: s.url,
      selection: TextSelection.collapsed(offset: s.url.length),
    );
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
        // No suggestions for the untouched current URL (select-all state).
        if (widget.suggest == null ||
            q.isEmpty ||
            value.text == widget.url ||
            !_focus.hasFocus) {
          return const <UrlSuggestion>[];
        }
        return widget.suggest!(q);
      },
      onSelected: (s) => _go(s.url),
      optionsViewBuilder: (context, onSelected, options) {
        // The field is narrow (it sits inside the AppBar), so the list is
        // widened to the screen and shifted left to start at the edge.
        final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
        final left = (box != null && box.attached && box.hasSize)
            ? box.localToGlobal(Offset.zero).dx
            : 0.0;
        final width = MediaQuery.of(context).size.width - 16;
        return _SuggestionList(
          options: options,
          onSelected: onSelected,
          onFill: _fill,
          width: width,
          shift: left - 8,
        );
      },
      fieldViewBuilder: (context, ctrl, focus, _) {
        // NOTE: we deliberately do NOT call the provided onFieldSubmitted:
        // it would pick the highlighted suggestion instead of what the user
        // typed.
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
                    : (widget.url.startsWith('https') ? Icons.lock : Icons.public),
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
    required this.shift,
  });

  final Iterable<UrlSuggestion> options;
  final AutocompleteOnSelected<UrlSuggestion> onSelected;
  final ValueChanged<UrlSuggestion> onFill;
  final double width;
  final double shift;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = options.toList(growable: false);
    return Align(
      alignment: Alignment.topLeft,
      child: Transform.translate(
        offset: Offset(-shift, 0),
        child: Material(
          elevation: 6,
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width, maxHeight: 360),
            child: SizedBox(
              width: width,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final s = list[i];
                  return ListTile(
                    dense: true,
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