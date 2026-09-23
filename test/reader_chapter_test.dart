import 'package:flutter_test/flutter_test.dart';
import 'package:vox_browser/models/page_probe.dart';
import 'package:vox_browser/models/reader_notice.dart';
import 'package:vox_browser/services/settings_service.dart';
import 'package:vox_browser/state/reader_controller.dart';

import 'helpers/reader_fakes.dart';

/// Finish the utterances of the chapter currently loaded.
Future<void> readToEnd(ReaderRig s) async {
  final n = s.r.chunks.length;
  for (var i = 0; i < n; i++) {
    s.tts.complete(s.tts.spoken.length - 1);
    await pumpEventQueue();
  }
}

Future<ReaderRig> rig([FakeRules? rules]) async {
  final s = await setupReader(rules: rules ?? FakeRules(nextRule));
  await s.r.play();
  await pumpEventQueue();
  return s;
}

void main() {
  group('advancing to the next chapter', () {
    test('clicks the saved element, then auto-reads the new chapter', () async {
      final s = await rig();
      s.page.onClick = () {
        switchTo(s.page, chapter2);
        return ClickResult.clicked;
      };

      await readToEnd(s);
      final ch2 = chunksOf(chapter2);
      await waitUntil(() => s.tts.spoken.last == ch2.first);

      expect(s.page.clicks, 1);
      expect(s.page.lastSelector, '#next');
      expect(s.r.chunks, ch2);
      expect(s.r.index, 0);
      expect(s.r.isPlaying, isTrue);
      expect(s.r.isAdvancing, isFalse);
      expect(s.r.notice, isNull);
      expect(s.page.applied.last.startNode, 1); // highlight on the NEW page
    });

    test('keeps going chapter after chapter, then stops when the button is gone',
        () async {
      final s = await rig();
      final queue = [chapter2, chapter3];
      s.page.onClick = () {
        if (queue.isEmpty) return ClickResult.notFound;
        switchTo(s.page, queue.removeAt(0));
        return ClickResult.clicked;
      };

      await readToEnd(s);
      await waitUntil(() => s.r.chunks == chunksOf(chapter2) && s.tts.spoken.last == chunksOf(chapter2).first);
      await readToEnd(s);
      await waitUntil(() => s.r.chunks == chunksOf(chapter3) && s.tts.spoken.last == chunksOf(chapter3).first);
      await readToEnd(s);
      await waitUntil(() => s.r.notice != null);

      expect(s.r.notice!.kind, NoticeKind.nextNotFound);
      expect(s.r.state, ReaderState.idle);
      expect(s.r.isPlaying, isFalse);
      expect(s.r.chaptersAdvanced, 2);
    });
  });

  group('failures stop auto-read and tell the user', () {
    test('element not found', () async {
      final s = await rig();
      s.page.onClick = () => ClickResult.notFound;
      await readToEnd(s);
      await waitUntil(() => s.r.notice != null);

      expect(s.r.notice!.kind, NoticeKind.nextNotFound);
      expect(s.r.notice!.message, contains('not found'));
      expect(s.r.state, ReaderState.idle);
      final spoken = s.tts.spoken.length;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(s.tts.spoken.length, spoken); // nothing more is read
    });

    test('element no longer clickable (with the reason)', () async {
      final s = await rig();
      s.page.onClick =
          () => const ClickResult(ClickStatus.notClickable, 'it is disabled');
      await readToEnd(s);
      await waitUntil(() => s.r.notice != null);

      expect(s.r.notice!.kind, NoticeKind.nextNotClickable);
      expect(s.r.notice!.message, contains('no longer clickable'));
      expect(s.r.notice!.message, contains('it is disabled'));
      expect(s.r.state, ReaderState.idle);
    });

    test('clickable, but the content never changes', () async {
      final s = await rig();
      await readToEnd(s); // click "works", page stays identical
      await waitUntil(() => s.r.notice != null);

      expect(s.page.clicks, 1);
      expect(s.r.notice!.kind, NoticeKind.nextNoChange);
      expect(s.r.notice!.message, contains('did not change'));
      expect(s.r.state, ReaderState.idle);
      expect(s.r.isAdvancing, isFalse);
    });

    test('cosmetic DOM changes (ads, counters) do not count as a new chapter',
        () async {
      final s = await rig();
      var n = 0;
      s.page.fingerprintOverride = () => PageFingerprint(
          url: 'https://x.test', title: 't', len: 100 + n++, head: 'h', tail: 't');

      await readToEnd(s);
      await waitUntil(() => s.r.notice != null);

      expect(s.r.notice!.kind, NoticeKind.nextNoChange);
      expect(s.page.extracts, greaterThan(1)); // it did verify the text
      expect(s.r.chunks, fixtureChunks()); // and kept the old chapter
    });

    test('navigation starts but never finishes', () async {
      final s = await rig();
      await readToEnd(s);
      await waitUntil(() => s.page.clicks == 1);
      s.r.onNavigationStarted();

      await waitUntil(() => s.r.notice != null);
      expect(s.r.notice!.kind, NoticeKind.nextTimeout);
      expect(s.r.state, ReaderState.idle);
    });
  });

  group('real page navigation', () {
    test('loadPage() completing the navigation takes over and auto-plays',
        () async {
      final s = await rig();
      await readToEnd(s);
      await waitUntil(() => s.page.clicks == 1);

      s.r.onNavigationStarted(); // WebView onLoadStart
      switchTo(s.page, chapter2);
      await s.r.loadPage(url: 'https://x.test/2'); // WebView onLoadStop
      await pumpEventQueue();

      final ch2 = chunksOf(chapter2);
      expect(s.r.chunks, ch2);
      expect(s.r.isPlaying, isTrue);
      expect(s.tts.spoken.last, ch2.first);
      expect(s.r.notice, isNull);
      expect(s.page.clicks, 1); // polling did not double-apply / re-click
    });

    test('navigating to identical content is reported, not looped', () async {
      final s = await rig();
      await readToEnd(s);
      await waitUntil(() => s.page.clicks == 1);

      s.r.onNavigationStarted();
      await s.r.loadPage(url: 'https://x.test'); // same chapter again
      await pumpEventQueue();

      expect(s.r.notice?.kind, NoticeKind.nextNoChange);
      expect(s.r.isPlaying, isFalse);
    });
  });

  group('configuration', () {
    test('no rule for this URL: finishes quietly', () async {
      final s = await rig(FakeRules(null));
      await readToEnd(s);
      await pumpEventQueue();
      expect(s.page.clicks, 0);
      expect(s.r.notice, isNull);
      expect(s.r.state, ReaderState.idle);
    });

    test('rule for a different site does not apply', () async {
      final s = await rig(FakeRules(
          nextRule.copyWith(urlPrefix: 'https://other.example/')));
      await readToEnd(s);
      await pumpEventQueue();
      expect(s.page.clicks, 0);
    });

    test('auto-advance switched off in settings', () async {
      final s = await rig();
      await s.r.applySettings(const AppSettings(autoNextChapter: false));
      await readToEnd(s);
      await pumpEventQueue();
      expect(s.page.clicks, 0);
      expect(s.r.state, ReaderState.idle);
    });

    test('pausing during the advance cancels it silently', () async {
      final s = await rig();
      await readToEnd(s);
      await waitUntil(() => s.page.clicks == 1);
      await s.r.pause();

      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(s.r.notice, isNull);
      expect(s.r.state, ReaderState.paused);
      expect(s.r.isAdvancing, isFalse);
    });
  });

  group('manual next chapter (button / notification)', () {
    test('works without auto-advance and starts reading', () async {
      final s = await setupReader(rules: FakeRules(nextRule));
      s.page.onClick = () {
        switchTo(s.page, chapter2);
        return ClickResult.clicked;
      };
      await s.r.nextChapter();
      final ch2 = chunksOf(chapter2);
      await waitUntil(() => s.tts.spoken.isNotEmpty && s.tts.spoken.last == ch2.first);
      expect(s.r.chunks, ch2);
    });

    test('without a saved button it explains how to set one', () async {
      final s = await setupReader(rules: FakeRules(null));
      await s.r.nextChapter();
      expect(s.r.notice?.kind, NoticeKind.noRule);
      expect(s.page.clicks, 0);
    });
  });
}