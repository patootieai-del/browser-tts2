import 'package:flutter_test/flutter_test.dart';
import 'package:vox_browser/core/utils/text_map.dart';

void main() {
  group('canon', () {
    test('keeps only lower-cased letters and digits', () {
      expect(TextMap.canon('Hello, World! 123'), 'helloworld123');
    });
    test('removes URLs', () {
      expect(TextMap.canon('See https://a.com/x?y=1 now'), 'seenow');
    });
    test('handles NBSP and accents', () {
      expect(TextMap.canon('Café\u00A0Déjà'), 'cafédéjà');
    });
  });

  group('locate', () {
    test('matches across whitespace/punctuation differences with exact offsets', () {
      final m = TextMap(['Hello,', '  world!  ', 'Next   sentence.']);
      final r = m.locateForIndex(0, 'Hello, world!')!;
      expect(r.startNode, 0);
      expect(r.startOffset, 0);
      expect(r.endNode, 1);
      expect(r.endOffset, 7); // just after the 'd' in '  world!  '
    });

    test('matches text split across nodes with no whitespace', () {
      final m = TextMap(['ab', 'cd']);
      final r = m.locateForIndex(0, 'abcd')!;
      expect((r.startNode, r.endNode, r.endOffset), (0, 1, 2));
    });

    test('ignores the period the reader adds after the title', () {
      final m = TextMap(['Nav', 'My Great Title', 'Body text goes here']);
      final r = m.locateForIndex(0, 'My Great Title. ')!;
      expect(r.startNode, 1);
    });

    test('is case-, NBSP- and accent-insensitive', () {
      final m = TextMap(['Café\u00A0Déjà vu']);
      expect(m.locateForIndex(0, 'café déjà vu'), isNotNull);
    });

    test('URLs stripped from the chunk are also ignored in the page', () {
      const node = 'Read more at https://example.com/a?b=1 today';
      final m = TextMap([node]);
      final r = m.locateForIndex(0, 'Read more at today')!;
      expect(r.startNode, 0);
      expect(r.endOffset, node.length);
    });

    test('repeated phrases resolve to the occurrence after the previous chunk', () {
      final m = TextMap(['Share this', 'Intro text here', 'Share this', 'More']);
      expect(m.locateForIndex(0, 'Intro text here')!.startNode, 1);
      // Without the cursor this would wrongly pick node 0 (the nav copy).
      expect(m.locateForIndex(1, 'Share this')!.startNode, 2);
    });

    test('first occurrence is used when there is no earlier chunk', () {
      final m = TextMap(['Share this', 'Intro', 'Share this']);
      expect(m.locateForIndex(0, 'Share this')!.startNode, 0);
    });

    test('returns null (never a wrong range) when text is absent', () {
      final m = TextMap(['Completely different content']);
      expect(m.locateForIndex(0, 'Something else entirely'), isNull);
    });

    test('head/tail fallback tolerates an inserted inline block', () {
      const p1 = 'The quick brown fox jumps over the lazy dog near the river bank';
      const p2 = 'and then the fox ran away into the deep green forest at dusk';
      final m = TextMap([p1, 'Advertisement inserted text', p2]);
      final r = m.locateForIndex(0, '$p1 $p2')!;
      expect(r.startNode, 0);
      expect(r.endNode, 2);
    });

    test('fallback refuses implausibly long spans', () {
      const p1 = 'The quick brown fox jumps over the lazy dog near the river bank';
      const p2 = 'and then the fox ran away into the deep green forest at dusk';
      final filler = List.generate(40, (i) => 'unrelated filler paragraph number $i');
      final m = TextMap([p1, ...filler, p2]);
      expect(m.locateForIndex(0, '$p1 $p2'), isNull);
    });
  });
}