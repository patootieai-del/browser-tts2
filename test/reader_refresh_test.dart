import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vox_browser/state/reader_controller.dart';

import 'helpers/reader_fakes.dart';

Future<void> settle() async {
  await Future<void>.delayed(const Duration(milliseconds: 5));
  await pumpEventQueue();
}

final _changed = makeArticle(
  const [
    'A brand new paragraph describes grapes and is long enough.',
    'Another new paragraph explains lemons and keeps on going.',
  ],
  title: 'A completely different page title that is long enough',
);
final _appended =
    makeArticle([...fixtureSentences, extraSentence], domLength: 5600);

void main() {
  group('restart', () {
    test('rebuilds from the live page when content changed, starts at top',
        () async {
      final s = await setupReader();
      await s.r.play();
      await pumpEventQueue();
      await s.r.seekTo(2);
      await pumpEventQueue();

      s.page.article = _changed;
      s.page.nodes = nodesFor(chunksOf(_changed));
      await s.r.restart();
      await pumpEventQueue();

      final fresh = chunksOf(_changed);
      expect(s.r.chunks, fresh);
      expect(s.r.index, 0);
      expect(s.r.state, ReaderState.playing); // was playing, still playing
      expect(s.tts.spoken.last, fresh[0]);
      expect(s.page.applied.last.startNode, 1); // highlight uses NEW page nodes
    });

    test('unchanged content: keeps the chunks, restarts from the top', () async {
      final s = await setupReader();
      final before = s.r.chunks;
      await s.r.play();
      await pumpEventQueue();
      await s.r.seekTo(3);
      await pumpEventQueue();
      final spokenBefore = s.tts.spoken.length;

      await s.r.restart();
      await pumpEventQueue();

      expect(identical(s.r.chunks, before), isTrue);
      expect(s.r.index, 0);
      expect(s.tts.spoken.length, spokenBefore + 1);
      expect(s.tts.spoken.last, before[0]);
    });

    test('while idle: stays idle at the top', () async {
      final s = await setupReader();
      await s.r.seekTo(2);
      await s.r.restart();
      await pumpEventQueue();
      expect(s.r.state, ReaderState.idle);
      expect(s.r.index, 0);
      expect(s.tts.spoken, isEmpty);
    });
  });

  group('refresh', () {
    test('keeps the position when content is appended', () async {
      final s = await setupReader();
      final old = s.r.chunks;
      await s.r.seekTo(2);

      s.page.article = _appended;
      s.page.nodes = nodesFor(chunksOf(_appended));
      await s.r.refresh();

      expect(s.r.chunks.length, old.length + 1);
      expect(s.r.index, 2);
      expect(s.r.chunks[2], old[2]);
    });

    test('goes to the top when the current sentence no longer exists', () async {
      final s = await setupReader();
      await s.r.seekTo(2);
      s.page.article = _changed;
      await s.r.refresh();
      expect(s.r.index, 0);
    });

    test('a failed extraction keeps the existing content', () async {
      final s = await setupReader();
      final before = s.r.chunks;
      s.page.article = null;
      await s.r.refresh();
      expect(identical(s.r.chunks, before), isTrue);
    });
  });

  group('SPA change detection', () {
    test('while playing: marks stale but never interrupts speech', () async {
      final s = await setupReader();
      await s.r.play();
      await pumpEventQueue();
      final spoken = s.tts.spoken.length;
      final chunks = s.r.chunks;

      s.page.article = _appended;
      s.r.onContentChanged(5600);
      await settle();

      expect(s.r.isStale, isTrue);
      expect(s.r.isPlaying, isTrue);
      expect(s.tts.spoken.length, spoken);
      expect(identical(s.r.chunks, chunks), isTrue);

      await s.r.refresh(); // user taps the banner
      await pumpEventQueue();
      expect(s.r.isStale, isFalse);
      expect(s.r.chunks.length, chunks.length + 1);
      expect(s.r.isPlaying, isTrue);
      expect(s.tts.spoken.last, s.r.chunks[s.r.index]);
    });

    test('while idle: rebuilds automatically', () async {
      final s = await setupReader();
      s.page.article = _appended;
      s.r.onContentChanged(5600);
      await settle();
      expect(s.r.chunks, chunksOf(_appended));
      expect(s.r.isStale, isFalse);
    });

    test('tiny changes (clock/counter) are ignored', () async {
      final s = await setupReader();
      final extracts = s.page.extracts;
      s.r.onContentChanged(5010);
      await settle();
      expect(s.r.isStale, isFalse);
      expect(s.page.extracts, extracts);
    });

    test('page that rendered nothing at load is picked up when content arrives',
        () async {
      final s = await setupReader(emptyPage: true);
      expect(s.r.hasContent, isFalse);

      s.page.article = fixtureArticle;
      s.page.nodes = fixtureNodes();
      s.r.onContentChanged(10);
      await settle();

      expect(s.r.hasContent, isTrue);
      expect(s.r.chunks, fixtureChunks());
    });

    test('route change while idle rebuilds; fragment-only change does not',
        () async {
      final s = await setupReader();
      final extracts = s.page.extracts;

      s.r.onRouteChanged('https://x.test#section');
      await settle();
      expect(s.page.extracts, extracts);

      s.page.article = _changed;
      s.r.onRouteChanged('https://x.test/next');
      await settle();
      expect(s.r.chunks, chunksOf(_changed));
    });

    test('route change while playing: stale bar only, speech untouched',
        () async {
      final s = await setupReader();
      await s.r.play();
      await pumpEventQueue();
      final spoken = s.tts.spoken.length;

      s.page.article = _changed;
      s.r.onRouteChanged('https://x.test/next');
      await settle();

      expect(s.r.isStale, isTrue);
      expect(s.r.isPlaying, isTrue);
      expect(s.tts.spoken.length, spoken);
      expect(listEquals(s.r.chunks, fixtureChunks()), isTrue);
    });
  });
}