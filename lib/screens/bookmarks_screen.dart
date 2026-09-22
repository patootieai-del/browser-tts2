import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/library_controller.dart';

class BookmarksScreen extends StatefulWidget {
  const BookmarksScreen({super.key});
  @override
  State<BookmarksScreen> createState() => _BookmarksScreenState();
}

class _BookmarksScreenState extends State<BookmarksScreen> {
  @override
  void initState() {
    super.initState();
    context.read<LibraryController>().refreshBookmarks();
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<LibraryController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarks')),
      body: lib.bookmarks.isEmpty
          ? const Center(child: Text('No bookmarks yet'))
          : ListView.separated(
              itemCount: lib.bookmarks.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final b = lib.bookmarks[i];
                return ListTile(
                  leading: const Icon(Icons.star, color: Colors.amber),
                  title: Text(b.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(b.url,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => lib.toggleBookmark(b.url, b.title),
                  ),
                  onTap: () => Navigator.pop(context, b.url),
                );
              },
            ),
    );
  }
}
