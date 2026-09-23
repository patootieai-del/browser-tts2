import 'package:flutter/foundation.dart';

import '../models/bookmark.dart';
import '../models/history_entry.dart';
import '../services/database_service.dart';
import '../core/utils/url_suggestions.dart';

class LibraryController extends ChangeNotifier {
  final _db = DatabaseService.instance;

  List<HistoryEntry> history = [];
  List<Bookmark> bookmarks = [];
  bool incognito = false;

  void setIncognito(bool v) {
    incognito = v;
    notifyListeners();
  }

  Future<void> recordVisit(String url, String title) async {
    if (url.isEmpty || url.startsWith('about:')) return;
    await _db.addVisit(HistoryEntry(
        url: url,
        title: title.isEmpty ? url : title,
        visitedAt: DateTime.now()));
  }

  Future<void> refreshHistory({String q = ''}) async {
    history = await _db.history(query: q);
    notifyListeners();
  }

  Future<void> deleteHistory(int id) async {
    await _db.deleteHistory(id);
    await refreshHistory();
  }

  Future<void> clearHistory({Duration? olderThan}) async {
    await _db.clearHistory(olderThan: olderThan);
    await refreshHistory();
  }

  Future<void> refreshBookmarks({String q = ''}) async {
    bookmarks = await _db.bookmarks(query: q);
    notifyListeners();
  }

  Future<bool> isBookmarked(String url) => _db.isBookmarked(url);

  Future<bool> toggleBookmark(String url, String title) async {
    final exists = await _db.isBookmarked(url);
    if (exists) {
      await _db.removeBookmarkByUrl(url);
    } else {
      await _db.addBookmark(
          Bookmark(url: url, title: title, createdAt: DateTime.now()));
    }
    await refreshBookmarks();
    return !exists;
  }

  Future<List<UrlSuggestion>> suggest(String query) async {
    try {
      return UrlRanker.rank(await _db.suggestionCandidates(query), query);
    } catch (_) {
      return const [];
    }
  }

  Future<List<UrlSuggestion>> recent() async {
    try {
      return UrlRanker.recent(await _db.recentHistory());
    } catch (_) {
      return const [];
    }
  }
}
