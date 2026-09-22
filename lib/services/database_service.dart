import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/bookmark.dart';
import '../models/history_entry.dart';

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, 'vox_browser.db'),
      version: 1,
      onCreate: (d, _) async {
        await d.execute('''
          CREATE TABLE history(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url TEXT NOT NULL,
            title TEXT NOT NULL,
            visited_at INTEGER NOT NULL
          )''');
        await d.execute(
            'CREATE INDEX idx_history_time ON history(visited_at DESC)');
        await d.execute('''
          CREATE TABLE bookmarks(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            url TEXT NOT NULL UNIQUE,
            title TEXT NOT NULL,
            folder TEXT NOT NULL DEFAULT 'Unsorted',
            created_at INTEGER NOT NULL
          )''');
      },
    );
  }

  // ---------- history ----------
  Future<void> addVisit(HistoryEntry e) async {
    final d = await db;
    // Collapse consecutive visits to the same URL.
    final last = await d.query('history',
        orderBy: 'visited_at DESC', limit: 1);
    if (last.isNotEmpty && last.first['url'] == e.url) {
      await d.update('history', {'visited_at': e.visitedAt.millisecondsSinceEpoch, 'title': e.title},
          where: 'id = ?', whereArgs: [last.first['id']]);
      return;
    }
    await d.insert('history', e.toMap()..remove('id'));
  }

  Future<List<HistoryEntry>> history({String query = '', int limit = 300}) async {
    final d = await db;
    final rows = query.isEmpty
        ? await d.query('history', orderBy: 'visited_at DESC', limit: limit)
        : await d.query('history',
            where: 'title LIKE ? OR url LIKE ?',
            whereArgs: ['%$query%', '%$query%'],
            orderBy: 'visited_at DESC',
            limit: limit);
    return rows.map(HistoryEntry.fromMap).toList();
  }

  Future<void> deleteHistory(int id) async {
    final d = await db;
    await d.delete('history', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearHistory({Duration? olderThan}) async {
    final d = await db;
    if (olderThan == null) {
      await d.delete('history');
    } else {
      final cutoff =
          DateTime.now().subtract(olderThan).millisecondsSinceEpoch;
      await d.delete('history', where: 'visited_at < ?', whereArgs: [cutoff]);
    }
  }

  // ---------- bookmarks ----------
  Future<void> addBookmark(Bookmark b) async {
    final d = await db;
    await d.insert('bookmarks', b.toMap()..remove('id'),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeBookmarkByUrl(String url) async {
    final d = await db;
    await d.delete('bookmarks', where: 'url = ?', whereArgs: [url]);
  }

  Future<bool> isBookmarked(String url) async {
    final d = await db;
    final r =
        await d.query('bookmarks', where: 'url = ?', whereArgs: [url], limit: 1);
    return r.isNotEmpty;
  }

  Future<List<Bookmark>> bookmarks({String query = ''}) async {
    final d = await db;
    final rows = query.isEmpty
        ? await d.query('bookmarks', orderBy: 'created_at DESC')
        : await d.query('bookmarks',
            where: 'title LIKE ? OR url LIKE ?',
            whereArgs: ['%$query%', '%$query%'],
            orderBy: 'created_at DESC');
    return rows.map(Bookmark.fromMap).toList();
  }
}