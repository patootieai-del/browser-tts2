import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chapter_rule.dart';

abstract class ChapterRuleLookup {
  ChapterRule? match(String url);
}

class ChapterRuleStore extends ChangeNotifier implements ChapterRuleLookup {
  static const _key = 'chapter_rules_v1';
  final List<ChapterRule> _rules = [];

  List<ChapterRule> get rules => List.unmodifiable(_rules);

  Future<void> load() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      if (raw != null) {
        _rules
          ..clear()
          ..addAll((jsonDecode(raw) as List)
              .map((e) => ChapterRule.fromJson(Map<String, dynamic>.from(e as Map))));
      }
    } catch (_) {
      _rules.clear();
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(_rules.map((r) => r.toJson()).toList()));
  }

  Future<void> upsert(ChapterRule rule) async {
    _rules.removeWhere(
        (r) => r.urlPrefix.toLowerCase() == rule.urlPrefix.toLowerCase());
    _rules.add(rule);
    notifyListeners();
    await _save();
  }

  Future<void> remove(String prefix) async {
    _rules.removeWhere((r) => r.urlPrefix == prefix);
    notifyListeners();
    await _save();
  }

  Future<void> setEnabled(String prefix, bool enabled) async {
    final i = _rules.indexWhere((r) => r.urlPrefix == prefix);
    if (i < 0) return;
    _rules[i] = _rules[i].copyWith(enabled: enabled);
    notifyListeners();
    await _save();
  }

  /// Longest matching enabled prefix wins.
  @override
  ChapterRule? match(String url) {
    ChapterRule? best;
    for (final r in _rules) {
      if (r.enabled &&
          r.matches(url) &&
          (best == null || r.urlPrefix.length > best.urlPrefix.length)) {
        best = r;
      }
    }
    return best;
  }
}