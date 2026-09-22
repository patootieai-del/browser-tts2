import 'package:flutter/material.dart';

class UrlBar extends StatefulWidget {
  const UrlBar({
    super.key,
    required this.url,
    required this.incognito,
    required this.onSubmit,
  });

  final String url;
  final bool incognito;
  final ValueChanged<String> onSubmit;

  @override
  State<UrlBar> createState() => _UrlBarState();
}

class _UrlBarState extends State<UrlBar> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
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
      _ctrl.text = widget.url; // always edit the full, current URL
      _selectAllSoon();
    } else if (!_submitted) {
      _ctrl.text = widget.url; // discard abandoned edits
    }
    if (_editing != has && mounted) setState(() => _editing = has);
  }

  void _selectAll() {
    if (!mounted || !_focus.hasFocus) return;
    _ctrl.selection =
        TextSelection(baseOffset: 0, extentOffset: _ctrl.text.length);
  }

  void _selectAllSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _selectAll());
  }

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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Listener(
      // Runs before the tap is processed, so we know if this tap is the one
      // that activates the field.
      onPointerDown: (_) => _hadFocusOnPointerDown = _focus.hasFocus,
      child: TextField(
        controller: _ctrl,
        focusNode: _focus,
        textInputAction: TextInputAction.go,
        keyboardType: TextInputType.url,
        autocorrect: false,
        enableSuggestions: false,
        onTap: () {
          if (!_hadFocusOnPointerDown) {
            _selectAll(); // after the tap placed the caret
            _selectAllSoon(); // and once more after the frame
          }
        },
        onSubmitted: (v) {
          _submitted = true;
          _focus.unfocus();
          widget.onSubmit(v);
        },
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
    );
  }
}