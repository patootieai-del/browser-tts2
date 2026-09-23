import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/bookmark.dart';
import '../models/history_entry.dart';
import '../core/utils/url_suggestions.dart';

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();

  Database? _db;
  // --------- suggestions ---------
  static String _escapeLike(String s) => s
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_'); // '_' is common in URLs

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    return openDatabase(
      p.join(dir, 'vox_browser.db'),
      version: 2,
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
        await d.execute('CREATE INDEX idx_history_url ON history(url)');
      },
      onUpgrade: (d, from, to) async {
        if (from < 2) {
          await d.execute(
              'CREATE INDEX IF NOT EXISTS idx_history_url ON history(url)');
        }
      },
    );
  }

  // ---------- history ----------
  Future<void> addVisit(HistoryEntry e) async {
    final d = await db;
    // Collapse consecutive visits to the same URL.
    final last = await d.query('history', orderBy: 'visited_at DESC', limit: 1);
    if (last.isNotEmpty && last.first['url'] == e.url) {
      await d.update('history',
          {'visited_at': e.visitedAt.millisecondsSinceEpoch, 'title': e.title},
          where: 'id = ?', whereArgs: [last.first['id']]);
      return;
    }
    await d.insert('history', e.toMap()..remove('id'));
  }

  Future<List<HistoryEntry>> history(
      {String query = '', int limit = 300}) async {
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
      final cutoff = DateTime.now().subtract(olderThan).millisecondsSinceEpoch;
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
    final r = await d.query('bookmarks',
        where: 'url = ?', whereArgs: [url], limit: 1);
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

  /// Coarse SQL pre-filter (longest token); UrlRanker does the real work.
  Future<List<UrlSuggestion>> suggestionCandidates(String query,
      {int perSource = 100}) async {
    final q = UrlRanker.normalizeQuery(query);
    if (q.isEmpty) return const [];
    final probe =
        q.split(RegExp(r'\s+')).reduce((a, b) => a.length >= b.length ? a : b);
    final like = '%${_escapeLike(probe)}%';
    final d = await db;
    final hist = await d.rawQuery(r'''
    SELECT url, MAX(title) AS title, COUNT(*) AS visits, MAX(visited_at) AS last
      FROM history
     WHERE url LIKE ? ESCAPE '\' OR title LIKE ? ESCAPE '\'
     GROUP BY url ORDER BY last DESC LIMIT ?''', [like, like, perSource]);
    final bms = await d.rawQuery(r'''
    SELECT url, title, created_at FROM bookmarks
     WHERE url LIKE ? ESCAPE '\' OR title LIKE ? ESCAPE '\'
     LIMIT ?''', [like, like, perSource]);
    return [
      for (final r in hist)
        UrlSuggestion(
          url: r['url'] as String,
          title: (r['title'] as String?) ?? '',
          visits: (r['visits'] as int?) ?? 1,
          lastVisit: DateTime.fromMillisecondsSinceEpoch(r['last'] as int),
        ),
      for (final r in bms)
        UrlSuggestion(
          url: r['url'] as String,
          title: (r['title'] as String?) ?? '',
          isBookmark: true,
          lastVisit:
              DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        ),
    ];
  }

  /// Newest visits first. Scans a bounded window, so it stays fast on huge
  /// histories; de-duplication happens in UrlRanker.recent.
  Future<List<UrlSuggestion>> recentHistory({int scan = 200}) async {
    final d = await db;
    final rows = await d.query('history',
        columns: ['url', 'title', 'visited_at'],
        orderBy: 'visited_at DESC',
        limit: scan);
    return [
      for (final r in rows)
        UrlSuggestion(
          url: r['url'] as String,
          title: (r['title'] as String?) ?? '',
          lastVisit:
              DateTime.fromMillisecondsSinceEpoch(r['visited_at'] as int),
        ),
    ];
  }
}
