import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/reader_controller.dart';
import '../models/article.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});
  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _scrollCtrl = ScrollController();
  final _keys = <int, GlobalKey>{};
  int _lastIndex = -1;

  void _autoScroll(int index) {
    if (index == _lastIndex) return;
    _lastIndex = index;
    final key = _keys[index];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          alignment: 0.35, duration: const Duration(milliseconds: 350));
    }
  }

  Article? _lastArticle; // import '../models/article.dart'

  @override
  Widget build(BuildContext context) {
    final r = context.watch<ReaderController>();
    final cs = Theme.of(context).colorScheme;
    final a = r.article;

    if (!identical(r.article, _lastArticle)) {
      // new page => drop old keys
      _keys.clear();
      _lastArticle = r.article;
      _lastIndex = -1;
    }

    if (r.index != _lastIndex) {
      // schedule only on change
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autoScroll(r.index);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reader'),
        actions: [
          IconButton(
            tooltip: 'Re-read page content',
            icon: const Icon(Icons.sync),
            onPressed: () => r.refresh(),
          ),
          IconButton(
            icon: Icon(r.isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: r.togglePlayPause,
          ),
        ],
      ),
      body: a == null
          ? const Center(child: Text('Nothing extracted yet.'))
          : ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
              itemCount: r.chunks.length + 1,
              itemBuilder: (ctx, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(a.title,
                            style: Theme.of(ctx)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        if ((a.byline ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(a.byline!,
                                style: Theme.of(ctx).textTheme.bodySmall),
                          ),
                        const Divider(height: 28),
                      ],
                    ),
                  );
                }
                final idx = i - 1;
                final active = idx == r.index;
                final key = _keys.putIfAbsent(idx, GlobalKey.new);
                return InkWell(
                  key: key,
                  onTap: () => r.seekTo(idx),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: active
                          ? cs.primaryContainer.withOpacity(.75)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      r.chunks[idx],
                      style: TextStyle(
                        fontSize: 18,
                        height: 1.6,
                        color: active
                            ? cs.onPrimaryContainer
                            : cs.onSurface.withOpacity(.9),
                        fontWeight:
                            active ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }
}
