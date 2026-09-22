import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vox_browser/core/utils/text_chunker.dart';
import 'package:vox_browser/core/utils/text_map.dart';
import 'package:vox_browser/models/article.dart';
import 'package:vox_browser/services/extraction_service.dart';
import 'package:vox_browser/services/speech_engine.dart';
import 'package:vox_browser/state/reader_controller.dart';

/// Fake TTS engine. Like Android engines, it completes the `speak` future of
/// a cancelled utterance when stop() is called, and the test can also
/// deliver such a completion *late* via [complete].
class FakeSpeech implements SpeechEngine {
  @override
  void Function(String message)? onError;

  final spoken = <String>[];
  final _completers = <Completer<void>>[];
  bool completeOnStop = true;

  @override
  Future<void> init() async {}

  @override
  Future<void> speak(String text) {
    spoken.add(text);
    final c = Completer<void>();
    _completers.add(c);
    return c.future;
  }

  /// Finish (or deliver a late completion for) the n-th utterance.
  void complete(int n) {
    if (!_completers[n].isCompleted) _completers[n].complete();
  }

  @override
  Future<void> stop() async {
    if (!completeOnStop) return;
    for (final c in _completers) {
      if (!c.isCompleted) c.complete();
    }
  }

  @override
  Future<bool> pause() async => false; // forces the stop+re-speak path
  @override
  Future<void> setRate(double v) async {}
  @override
  Future<void> setPitch(double v) async {}
  @override
  Future<void> setVolume(double v) async {}
  @override
  Future<void> applyVoice(String? n, String? l) async {}
}

class FakePage implements PageContentSource {
  FakePage(this.article, this.nodes, {this.snapshotGate});
  final Article article;
  final List<String> nodes;
  final Completer<void>? snapshotGate;

  final applied = <HighlightRange>[];
  var snapshots = 0;

  @override
  Future<Article?> extract() async => article;

  @override
  Future<List<String>> snapshotTextNodes() async {
    snapshots++;
    await snapshotGate?.future;
    return nodes;
  }

  @override
  Future<bool> highlight(HighlightRange r) async {
    applied.add(r);
    return true;
  }

  @override
  Future<void> clearHighlight({bool release = false}) async {}
}

const _title = 'Fruit report: a title that is comfortably long enough';
const _sentences = [
  'The first sentence talks about apples and is long enough.',
  'The second sentence talks about bananas and is also long.',
  'The third sentence talks about cherries and keeps going.',
  'The fourth sentence talks about dates and finally ends.',
];

final _article = Article(
    title: _title, url: 'https://x.test', text: _sentences.join(' '));

List<String> _chunks() => TextChunker.chunk('$_title. \n\n${_sentences.join(' ')}');

/// Page text: a nav blob, then one node per chunk with messy whitespace.
/// => chunk i lives in node i + 1.
List<String> _nodes({int? replaceChunk}) {
  final c = _chunks();
  return [
    'Home Menu Login',
    for (var i = 0; i < c.length; i++)
      i == replaceChunk ? 'totally unrelated advertisement' : '  ${c[i]}\n',
  ];
}

Future<({ReaderController r, FakeSpeech tts, FakePage page})> _setup({
  List<String>? nodes,
  Completer<void>? gate,
}) async {
  final tts = FakeSpeech();
  final page = FakePage(_article, nodes ?? _nodes(), snapshotGate: gate);
  final r = ReaderController(tts: tts, extractor: ExtractionService());
  r.bindSource(page);
  await r.loadPage();
  return (r: r, tts: tts, page: page);
}

void main() {
  test('precondition: the fixture produces 5 distinct chunks', () {
    expect(_chunks().length, 5);
  });

  test('spoken chunk, highlighted chunk and index always agree', () async {
    final s = await _setup();
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
    final s = await _setup();
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
    final s = await _setup();
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
    final s = await _setup(gate: gate);

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
    final s = await _setup();
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
    final s = await _setup(nodes: _nodes(replaceChunk: 2));

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
    final s = await _setup();
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
    final slow = _SlowPage(_article, _nodes());
    final r = ReaderController(tts: tts, extractor: ExtractionService());
    r.bindSource(slow);
    final pending = r.loadPage();
    await pumpEventQueue();

    r.bindSource(FakePage(_article, _nodes())); // user switched tab
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
  Future<Article?> extract() async {
    await _gate.future;
    return article;
  }
}