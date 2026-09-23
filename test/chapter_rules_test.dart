import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vox_browser/models/chapter_rule.dart';
import 'package:vox_browser/state/chapter_rule_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ChapterRule r(String p, [String sel = '#n']) =>
      ChapterRule(urlPrefix: p, selector: sel);

  test('longest matching prefix wins', () async {
    final s = ChapterRuleStore();
    await s.upsert(r('https://site.com/', '#site'));
    await s.upsert(r('https://site.com/novel/1/', '#novel'));
    expect(s.match('https://site.com/novel/1/ch-5')!.selector, '#novel');
    expect(s.match('https://site.com/other')!.selector, '#site');
    expect(s.match('https://elsewhere.com/'), isNull);
  });

  test('matching ignores case and disabled rules', () async {
    final s = ChapterRuleStore();
    await s.upsert(r('https://Site.com/Novel/'));
    expect(s.match('https://site.com/novel/ch1'), isNotNull);
    await s.setEnabled('https://Site.com/Novel/', false);
    expect(s.match('https://site.com/novel/ch1'), isNull);
  });

  test('upsert replaces a rule with the same prefix', () async {
    final s = ChapterRuleStore();
    await s.upsert(r('https://a.com/', '#old'));
    await s.upsert(r('https://a.com/', '#new'));
    expect(s.rules.length, 1);
    expect(s.rules.single.selector, '#new');
  });

  test('rules persist', () async {
    final a = ChapterRuleStore();
    await a.upsert(ChapterRule(
        urlPrefix: 'https://a.com/', selector: 'a.next', label: 'Next'));
    final b = ChapterRuleStore();
    await b.load();
    expect(b.rules.single.selector, 'a.next');
    expect(b.rules.single.label, 'Next');
  });

  group('PrefixSuggestions', () {
    test('site, folder and exact', () {
      final p =
          PrefixSuggestions.of('https://site.com/novel/1/chapter-5?x=1#top');
      expect(p.site, 'https://site.com/');
      expect(p.folder, 'https://site.com/novel/1/');
      expect(p.exact, 'https://site.com/novel/1/chapter-5');
    });
    test('root-level pages', () {
      final p = PrefixSuggestions.of('https://site.com/chapter-5');
      expect(p.folder, 'https://site.com/');
      expect(
          PrefixSuggestions.of('https://site.com').folder, 'https://site.com/');
    });
    test('keeps ports', () {
      expect(PrefixSuggestions.of('http://localhost:8080/a/b').folder,
          'http://localhost:8080/a/');
    });
  });
}
