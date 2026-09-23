import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vox_browser/core/utils/text_chunker.dart';
import 'package:vox_browser/core/utils/text_map.dart';
import 'package:vox_browser/models/article.dart';
import 'package:vox_browser/services/extraction_service.dart';
import 'package:vox_browser/services/speech_engine.dart';
import 'package:vox_browser/state/reader_controller.dart';
import 'helpers/reader_fakes.dart';

const _title = 'Fruit report: a title that is comfortably long enough';
const _sentences = [
  'The first sentence talks about apples and is long enough.',
  'The second sentence talks about bananas and is also long.',
  'The third sentence talks about cherries and keeps going.',
  'The fourth sentence talks about dates and finally ends.',
];

final fixtureArticle = Article(
    title: _title, url: 'https://x.test', text: _sentences.join(' '));

List<String> fixtureChunks() => TextChunker.chunk('$_title. \n\n${_sentences.join(' ')}');

/// Page text: a nav blob, then one node per chunk with messy whitespace.
/// => chunk i lives in node i + 1.
List<String> fixtureNodes({int? replaceChunk}) {
  final c = fixtureChunks();
  return [
    'Home Menu Login',
    for (var i = 0; i < c.length; i++)
      i == replaceChunk ? 'totally unrelated advertisement' : '  ${c[i]}\n',
  ];
}

Future<({ReaderController r, FakeSpeech tts, FakePage page})> setupReader({
  List<String>? nodes,
  Completer<void>? gate,
}) async {
  final tts = FakeSpeech();
  final page = FakePage(fixtureArticle, nodes ?? fixtureNodes(), snapshotGate: gate);
  final r = ReaderController(tts: tts, extractor: ExtractionService());
  r.bindSource(page);
  await r.loadPage();
  return (r: r, tts: tts, page: page);
}

void main() {
  test('precondition: the fixture produces 5 distinct chunks', () {
    expect(fixtureChunks().length, 5);
  });

  test('spoken chunk, highlighted chunk and index always agree', () async {
    final s = await setupReader();
    final chunks = s.r.chunks;

    await s.r.play();
    await pumpEventQueue();

    for (var i = 0; i < chunks.length; i++) {
      expect(s.tts.spoken.last, chunks[i], reason: 'spoken @$i');
      expect(s.r.index, i, reason: 'index @$i');
      expect(s.page.applied.length, i + 1);
      expect(s.page.applied.last.startNode, i + 1, reason: 'highlight @$i');
      s.tts.complete(i);
      await pumpEventQueue();
    }
    expect(s.r.state, ReaderState.idle);
    expect(s.tts.spoken, chunks); // nothing skipped, nothing repeated
  });

  test('REGRESSION: late completion of a cancelled utterance must not advance',
      () async {
    final s = await setupReader();
    final chunks = s.r.chunks;

    await s.r.play();
    await pumpEventQueue(); // speaking chunk 0
    await s.r.next();
    await pumpEventQueue(); // speaking chunk 1

    s.tts.complete(0); // stale completion arrives AFTER the skip
    await pumpEventQueue();

    expect(s.r.index, 1);
    expect(s.tts.spoken, [chunks[0], chunks[1]]); // no extra chunk
    expect(s.page.applied.last.startNode, 2); // highlight == chunk 1
  });

  test('stale completions are ignored even if the engine completes on stop()',
      () async {
    final s = await setupReader();
    s.tts.completeOnStop = true;
    await s.r.play();
    await pumpEventQueue();

    await s.r.next();
    await s.r.next();
    await s.r.previous();
    await pumpEventQueue();

    expect(s.r.index, 1);
    expect(s.tts.spoken.last, s.r.chunks[1]);
    expect(s.page.applied.last.startNode, 2);
  });

  test('rapid skipping applies only the latest highlight', () async {
    final gate = Completer<void>();
    final s = await setupReader(gate: gate);

    await s.r.play();
    await pumpEventQueue(); // highlight(0) is waiting for the page snapshot
    await s.r.next();
    await s.r.next();
    await s.r.next();
    await pumpEventQueue();

    gate.complete(); // snapshot finally arrives
    await pumpEventQueue();

    expect(s.page.snapshots, 1); // shared, not one per request
    expect(s.page.applied.length, 1); // stale requests were dropped
    expect(s.r.index, 3);
    expect(s.page.applied.single.startNode, 4);
    expect(s.tts.spoken.last, s.r.chunks[3]);
  });

  test('pause then play re-speaks the same chunk without skipping', () async {
    final s = await setupReader();
    await s.r.play();
    await pumpEventQueue();

    await s.r.pause(); // fake has no native pause -> stop() completes future
    await pumpEventQueue();
    expect(s.r.state, ReaderState.paused);
    expect(s.r.index, 0); // the cancelled utterance did not advance

    await s.r.play();
    await pumpEventQueue();

    expect(s.tts.spoken, [s.r.chunks[0], s.r.chunks[0]]);
    expect(s.r.index, 0);
    expect(s.page.applied.last.startNode, 1);
  });

  test('no confident match => no highlight is applied (never a wrong one)',
      () async {
    final s = await setupReader(nodes: fixtureNodes(replaceChunk: 2));

    await s.r.play();
    await pumpEventQueue();
    s.tts.complete(0);
    await pumpEventQueue();
    s.tts.complete(1);
    await pumpEventQueue(); // now speaking chunk 2, which is not in the page

    expect(s.r.index, 2);
    expect(s.page.applied.map((r) => r.startNode).toList(), [1, 2]);
    // chunk 2 (node 3) must not have been highlighted:
    expect(s.page.applied.any((r) => r.startNode == 3), isFalse);
  });

  test('going back re-highlights the earlier chunk correctly', () async {
    final s = await setupReader();
    await s.r.play();
    await pumpEventQueue();
    await s.r.seekTo(3);
    await pumpEventQueue();
    await s.r.seekTo(1);
    await pumpEventQueue();

    expect(s.r.index, 1);
    expect(s.tts.spoken.last, s.r.chunks[1]);
    expect(s.page.applied.last.startNode, 2);
  });

  test('a stale page extraction does not replace the current page', () async {
    final tts = FakeSpeech();
    final slow = _SlowPage(fixtureArticle, fixtureNodes());
    final r = ReaderController(tts: tts, extractor: ExtractionService());
    r.bindSource(slow);
    final pending = r.loadPage();
    await pumpEventQueue();

    r.bindSource(FakePage(fixtureArticle, fixtureNodes())); // user switched tab
    slow.release();
    await pending;

    expect(r.hasContent, isFalse); // old result discarded
  });
}

class _SlowPage extends FakePage {
  _SlowPage(super.a, super.n);
  final _gate = Completer<void>();
  void release() => _gate.complete();
  @override
  Future<Article?> extract({bool settle = false}) async {
    await _gate.future;
    return article;
  }
}