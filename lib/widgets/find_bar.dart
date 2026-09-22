import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/browser_tab.dart';
import '../state/tabs_controller.dart';

class FindBar extends StatefulWidget {
  const FindBar({super.key, required this.tab});
  final BrowserTab tab;
  @override
  State<FindBar> createState() => _FindBarState();
}

class _FindBarState extends State<FindBar> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _search(String q) {
    final f = widget.tab.find;
    if (f == null) return;
    if (q.isEmpty) {
      f.clearMatches();
      widget.tab.findResult.value = (0, 0);
    } else {
      f.findAll(find: q);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                  isDense: true, hintText: 'Find on page'),
              onChanged: _search,
              onSubmitted: (_) => tab.find?.findNext(forward: true),
            ),
          ),
          ValueListenableBuilder<(int, int)>(
            valueListenable: tab.findResult,
            builder: (_, r, __) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(r.$2 == 0 ? '0/0' : '${r.$1 + 1}/${r.$2}'),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_up),
            onPressed: () => tab.find?.findNext(forward: false),
          ),
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => tab.find?.findNext(forward: true),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => context.read<TabsController>().closeFind(tab),
          ),
        ]),
      ),
    );
  }
}