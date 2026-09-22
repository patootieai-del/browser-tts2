import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/browser_tab.dart';
import '../state/tabs_controller.dart';

class TabSwitcherScreen extends StatelessWidget {
  const TabSwitcherScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tabs = context.watch<TabsController>();
    final nav = Navigator.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('${tabs.count} tabs'),
        actions: [
          IconButton(
            tooltip: 'New incognito tab',
            icon: const Icon(Icons.visibility_off),
            onPressed: () {
              tabs.newTab(incognito: true);
              nav.pop();
            },
          ),
          IconButton(
            tooltip: 'Close all',
            icon: const Icon(Icons.delete_sweep),
            onPressed: () {
              tabs.closeAll();
              nav.pop();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          tabs.newTab();
          nav.pop();
        },
        child: const Icon(Icons.add),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: .78),
        itemCount: tabs.count,
        itemBuilder: (ctx, i) {
          final t = tabs.tabs[i];
          return _TabCard(
            tab: t,
            selected: tabs.isActive(t),
            onTap: () {
              tabs.select(t.id);
              nav.pop();
            },
          );
        },
      ),
    );
  }
}

class _TabCard extends StatelessWidget {
  const _TabCard(
      {required this.tab, required this.selected, required this.onTap});
  final BrowserTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tabs = context.read<TabsController>();
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: selected ? cs.primary : Colors.transparent, width: 2),
      ),
      child: InkWell(
        onTap: onTap,
        child: Column(children: [
          SizedBox(
            height: 40,
            child: Row(children: [
              const SizedBox(width: 8),
              Icon(tab.incognito ? Icons.visibility_off : Icons.public, size: 16),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(tab.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13))),
              PopupMenuButton<String>(
                iconSize: 18,
                onSelected: (v) {
                  switch (v) {
                    case 'dup':
                      tabs.duplicate(tab.id);
                    case 'others':
                      tabs.closeOthers(tab.id);
                    case 'close':
                      tabs.closeTab(tab.id);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'dup', child: Text('Duplicate')),
                  PopupMenuItem(value: 'others', child: Text('Close others')),
                  PopupMenuItem(value: 'close', child: Text('Close')),
                ],
              ),
            ]),
          ),
          Expanded(
            child: SizedBox.expand(
              child: tab.thumbnail != null
                  ? Image.memory(tab.thumbnail!,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      cacheWidth: 300,
                      gaplessPlayback: true)
                  : ColoredBox(
                      color: cs.surfaceContainerHighest,
                      child: Center(
                          child: Text(
                              Uri.tryParse(tab.url)?.host ?? '',
                              style: TextStyle(color: cs.onSurfaceVariant))),
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}