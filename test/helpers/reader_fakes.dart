import 'dart:async';
import 'dart:math' as math;

import 'package:vox_browser/core/utils/text_chunker.dart';
import 'package:vox_browser/core/utils/text_map.dart';
import 'package:vox_browser/models/article.dart';
import 'package:vox_browser/services/extraction_service.dart';
import 'package:vox_browser/services/speech_engine.dart';
import 'package:vox_browser/state/reader_controller.dart';
import 'package:flutter_test/flutter_test.dart' show pumpEventQueue;
import 'package:vox_browser/models/chapter_rule.dart';
import 'package:vox_browser/models/page_probe.dart';
import 'package:vox_browser/state/chapter_rule_store.dart';

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
  Future<bool> pause() async => false;
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
  Article? article; // null => "nothing rendered yet"
  List<String> nodes;
  final Completer<void>? snapshotGate;

  final applied = <HighlightRange>[];
  var snapshots = 0;
  var extracts = 0;

  ClickResult Function()? onClick; // default: ClickResult.clicked
  PageFingerprint? Function()? fingerprintOverride;
  var clicks = 0;
  String? lastSelector;

  @override
  Future<PageFingerprint?> fingerprint() async {
    if (fingerprintOverride != null) return fingerprintOverride!();
    final a = article;
    if (a == null) return null;
    final t = a.text;
    return PageFingerprint(
        url: a.url,
        title: a.title,
        len: t.length,
        head: t.substring(0, math.min(300, t.length)),
        tail: t.substring(math.max(0, t.length - 300)));
  }

  @override
  Future<ClickResult> clickElement(String selector) async {
    clicks++;
    lastSelector = selector;
    return onClick?.call() ?? ClickResult.clicked;
  }

  @override
  Future<Article?> extract({bool settle = false}) async {
    extracts++;
    return article;
  }

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

const fixtureTitle = 'Fruit report: a title that is comfortably long enough';
const fixtureSentences = [
  'The first sentence talks about apples and is long enough.',
  'The second sentence talks about bananas and is also long.',
  'The third sentence talks about cherries and keeps going.',
  'The fourth sentence talks about dates and finally ends.',
];
const extraSentence = 'A fifth sentence was appended later about elderberries.';

Article makeArticle(List<String> sentences,
        {int domLength = 5000, String title = fixtureTitle}) =>
    Article(
        title: title,
        url: 'https://x.test',
        text: sentences.join(' '),
        domLength: domLength);

final fixtureArticle = makeArticle(fixtureSentences);

List<String> chunksOf(Article a) =>
    TextChunker.chunk('${a.title}. \n\n${a.text}');
List<String> fixtureChunks() => chunksOf(fixtureArticle);

/// Nav blob + one messy node per chunk => chunk i lives in node i + 1.
List<String> nodesFor(List<String> chunks, {int? replaceChunk}) => [
      'Home Menu Login',
      for (var i = 0; i < chunks.length; i++)
        i == replaceChunk
            ? 'totally unrelated advertisement'
            : '  ${chunks[i]}\n',
    ];
List<String> fixtureNodes({int? replaceChunk}) =>
    nodesFor(fixtureChunks(), replaceChunk: replaceChunk);

class ReaderRig {
  ReaderRig(this.r, this.tts, this.page);
  final ReaderController r;
  final FakeSpeech tts;
  final FakePage page;
}

Future<ReaderRig> setupReader({
  List<String>? nodes,
  Completer<void>? gate,
  bool emptyPage = false,
  ChapterRuleLookup? rules,
}) async {
  final tts = FakeSpeech();
  final page = FakePage(
      emptyPage ? null : fixtureArticle, nodes ?? fixtureNodes(),
      snapshotGate: gate);
  final r = ReaderController(
    tts: tts,
    extractor: ExtractionService(),
    rules: rules,
    autoRefreshDelay: Duration.zero,
    autoRefreshMinGap: Duration.zero,
    advancePoll: const Duration(milliseconds: 5),
    advanceNoChangeTimeout: const Duration(milliseconds: 150),
    advanceLoadTimeout: const Duration(milliseconds: 300),
  );
  r.bindSource(page);
  await r.loadPage(url: 'https://x.test');
  return ReaderRig(r, tts, page);
}

// --- fixtures ---
class FakeRules implements ChapterRuleLookup {
  FakeRules(this.rule);
  ChapterRule? rule;
  @override
  ChapterRule? match(String url) =>
      (rule != null && rule!.matches(url)) ? rule : null;
}

const nextRule =
    ChapterRule(urlPrefix: 'https://x.test', selector: '#next', label: 'Next');
final chapter2 = makeArticle(const [
  'Chapter two begins with a long sentence about grapes.',
  'The second paragraph of chapter two is about lemons too.',
], title: 'Chapter two: a heading that is long enough to stand alone');
final chapter3 = makeArticle(const [
  'Chapter three opens with a long sentence about melons.',
  'The closing paragraph of chapter three mentions figs.',
], title: 'Chapter three: another heading long enough to stand alone');
void switchTo(FakePage p, Article a) {
  p.article = a;
  p.nodes = nodesFor(chunksOf(a));
}

Future<void> waitUntil(bool Function() test,
    {Duration timeout = const Duration(seconds: 2)}) async {
  final sw = Stopwatch()..start();
  while (!test()) {
    if (sw.elapsed > timeout) throw StateError('waitUntil timed out');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await pumpEventQueue();
  }
}
