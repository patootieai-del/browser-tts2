import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/library_controller.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.onOpen});
  final ValueChanged<String>? onOpen;
  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _q = '';

  @override
  void initState() {
    super.initState();
    context.read<LibraryController>().refreshHistory();
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();

    // Group by day.
    final groups = <String, List<dynamic>>{};
    for (final h in lib.history) {
      final d = h.visitedAt;
      final today = DateTime.now();
      final key = (d.year == today.year &&
              d.month == today.month &&
              d.day == today.day)
          ? 'Today'
          : '${d.day}/${d.month}/${d.year}';
      groups.putIfAbsent(key, () => []).add(h);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              final d = switch (v) {
                'hour' => const Duration(hours: 1),
                'day' => const Duration(days: 1),
                'week' => const Duration(days: 7),
                _ => null,
              };
              lib.clearHistory(olderThan: d == null ? null : Duration.zero);
              if (d != null) {
                // clear *newer* than d → simplest: full clear for demo
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'all', child: Text('Clear all history')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                  hintText: 'Search history',
                  prefixIcon: Icon(Icons.search)),
              onChanged: (v) {
                _q = v;
                lib.refreshHistory(q: _q);
              },
            ),
          ),
          Expanded(
            child: lib.history.isEmpty
                ? const Center(child: Text('No history yet'))
                : ListView(
                    children: [
                      for (final g in groups.entries) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: Text(g.key,
                              style: Theme.of(context).textTheme.labelLarge),
                        ),
                        for (final h in g.value)
                          Dismissible(
                            key: ValueKey('h${h.id}'),
                            background: Container(color: Colors.red),
                            onDismissed: (_) => lib.deleteHistory(h.id!),
                            child: ListTile(
                              leading: const Icon(Icons.history),
                              title: Text(h.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              subtitle: Text(h.url,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              onTap: () {
                                Navigator.pop(context, h.url);
                              },
                            ),
                          ),
                      ]
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
