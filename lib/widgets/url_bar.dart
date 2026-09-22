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

  @override
  void initState() {
    super.initState();
    _ctrl.text = widget.url;          // <-- add
    _focus.addListener(() { /* unchanged */ });
  }

  @override
  void didUpdateWidget(covariant UrlBar old) {
    super.didUpdateWidget(old);
    if (!_editing && widget.url != old.url) _ctrl.text = widget.url;
  }

  String get _display {
    if (widget.url.isEmpty) return 'Search or type a URL';
    try {
      final u = Uri.parse(widget.url);
      return u.host.isEmpty ? widget.url : u.host.replaceFirst('www.', '');
    } catch (_) {
      return widget.url;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextField(
      controller: _ctrl,
      focusNode: _focus,
      textInputAction: TextInputAction.go,
      keyboardType: TextInputType.url,
      autocorrect: false,
      onSubmitted: (v) {
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
        suffixIcon: _editing && _ctrl.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => _ctrl.clear(),
              )
            : null,
      ),
      // Show the host when not editing.
      style: TextStyle(fontSize: 14, color: cs.onSurface),
      buildCounter: null,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }
}
