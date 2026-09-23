import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/utils/text_chunker.dart';
import '../core/utils/text_map.dart';
import '../models/article.dart';
import '../models/page_probe.dart';
import '../models/reader_notice.dart';
import '../services/extraction_service.dart';
import '../services/settings_service.dart';
import '../services/speech_engine.dart';
import 'chapter_rule_store.dart';

enum ReaderState { idle, extracting, playing, paused, error }

class _Fresh {
  const _Fresh(this.article, this.chunks);
  final Article article;
  final List<String> chunks;
}

/// INVARIANT: the chunk that is spoken, highlighted and [index] always agree
/// (token-guarded loop; see _run).
///
/// CHAPTERS: when the last chunk ends and a next-chapter rule matches the
/// page URL, the saved element is clicked and reading continues with the new
/// content. ANY failure stops auto-read and raises a [ReaderNotice].
class ReaderController extends ChangeNotifier {
  ReaderController({
    required SpeechEngine tts,
    required ExtractionService extractor,
    ChapterRuleLookup? rules,
    this.autoRefreshDelay = const Duration(milliseconds: 1200),
    this.autoRefreshMinGap = const Duration(seconds: 5),
    this.advancePoll = const Duration(milliseconds: 500),
    this.advanceNoChangeTimeout = const Duration(seconds: 10),
    this.advanceLoadTimeout = const Duration(seconds: 30),
  })  : _tts = tts,
        _extractor = extractor,
        _rules = rules {
    _tts.onError = (m) {
      if (_disposed) return;
      _sessionToken++;
      _cancelAdvance();
      _error = m;
      _state = ReaderState.error;
      notifyListeners();
    };
  }

  final SpeechEngine _tts;
  final ExtractionService _extractor;
  final ChapterRuleLookup? _rules;
  final Duration autoRefreshDelay;
  final Duration autoRefreshMinGap;
  final Duration advancePoll;
  final Duration advanceNoChangeTimeout;
  final Duration advanceLoadTimeout;

  InAppWebViewController? _webRef;
  PageContentSource? _source;
  Future<TextMap>? _mapFuture;
  AppSettings _settings = const AppSettings();

  Article? _article;
  List<String> _chunks = const [];
  int _index = 0;
  ReaderState _state = ReaderState.idle;
  String? _error;
  bool _disposed = false;

  String? _pageUrl;
  int _baselineLen = 0;
  bool _stale = false;
  Timer? _autoTimer;
  DateTime _lastAuto = DateTime.fromMillisecondsSinceEpoch(0);

  // chapter advance
  bool _advancing = false;
  bool _navStarted = false;
  int _advToken = 0;
  List<String> _advBeforeChunks = const [];
  ReaderNotice? _notice;
  int _chaptersAdvanced = 0;

  int _sessionToken = 0;
  int _loadToken = 0;
  int _hlToken = 0;
  int _opSeq = 0;

  Article? get article => _article;
  List<String> get chunks => _chunks;
  int get index => _index;
  ReaderState get state => _state;
  String? get error => _error;
  bool get hasContent => _chunks.isNotEmpty;
  bool get isPlaying => _state == ReaderState.playing;
  bool get isStale => _stale;
  bool get isAdvancing => _advancing;
  ReaderNotice? get notice => _notice;
  int get chaptersAdvanced => _chaptersAdvanced;
  String get currentChunk =>
      (_index >= 0 && _index < _chunks.length) ? _chunks[_index] : '';
  double get progress => _chunks.isEmpty ? 0 : (_index + 1) / _chunks.length;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void clearNotice() {
    if (_notice == null) return;
    _notice = null;
    _notify();
  }

  // ------------------------------------------------------------- binding
  void bind(InAppWebViewController? c) {
    if (identical(c, _webRef)) return;
    _webRef = c;
    bindSource(c == null ? null : _extractor.forController(c));
  }

  void bindSource(PageContentSource? s) {
    _sessionToken++;
    _loadToken++;
    _hlToken++;
    _opSeq++;
    _cancelAdvance();
    _autoTimer?.cancel();
    _autoTimer = null;
    unawaited(_tts.stop());
    final old = _source;
    if (old != null) unawaited(old.clearHighlight(release: true));
    _source = s;
    _mapFuture = null;
    _article = null;
    _chunks = const [];
    _index = 0;
    _error = null;
    _notice = null;
    _pageUrl = null;
    _baselineLen = 0;
    _stale = false;
    _state = ReaderState.idle;
    _notify();
  }

  Future<void> applySettings(AppSettings s) async {
    final rateChanged = s.speechRate != _settings.speechRate;
    final pitchChanged = s.pitch != _settings.pitch;
    final volChanged = s.volume != _settings.volume;
    final voiceChanged = s.voiceName != _settings.voiceName;
    _settings = s;

    await _tts.init();
    if (rateChanged) await _tts.setRate(s.speechRate);
    if (pitchChanged) await _tts.setPitch(s.pitch);
    if (volChanged) await _tts.setVolume(s.volume);
    if (voiceChanged) await _tts.applyVoice(s.voiceName, s.voiceLocale);

    if (isPlaying && !_advancing && (rateChanged || pitchChanged || voiceChanged)) {
      _sessionToken++;
      await _tts.stop();
      if (isPlaying && !_disposed) unawaited(_run());
    }
  }

  // -------------------------------------------------------------- loading
  /// Full (re)load of a NEW page. If a chapter advance is in flight this is
  /// its "arrival": it takes over and auto-plays.
  Future<void> loadPage({bool autoPlay = false, String? url}) async {
    final src = _source;
    final takeover = _advancing;
    final beforeChunks = _advBeforeChunks;
    _cancelAdvance();

    final my = ++_loadToken;
    _sessionToken++;
    _hlToken++;
    _opSeq++;
    _autoTimer?.cancel();
    _mapFuture = null;
    _article = null;
    _chunks = const [];
    _index = 0;
    _error = null;
    _stale = false;
    if (url != null) _pageUrl = url;
    _state = ReaderState.extracting;
    _notify();
    await _tts.stop();
    if (src != null) unawaited(src.clearHighlight(release: true));
    if (my != _loadToken || _disposed) return;

    if (src == null) {
      _state = ReaderState.idle;
      _notify();
      return;
    }

    final f = await _extractFresh(src);
    if (my != _loadToken || _disposed) return;

    if (f == null) {
      if (takeover) return _failAdvance(NoticeKind.nextEmpty);
      _state = ReaderState.idle;
      _error = 'No readable text found on this page.';
      _notify();
      return;
    }
    if (takeover && listEquals(f.chunks, beforeChunks)) {
      return _failAdvance(NoticeKind.nextNoChange); // navigated to same content
    }

    _applyFresh(f, keepPosition: false);
    if (takeover) _chaptersAdvanced++;
    _state = ReaderState.idle;
    _notify();
    if ((autoPlay || takeover) && _chunks.isNotEmpty) await play();
  }

  Future<_Fresh?> _extractFresh(PageContentSource src) async {
    Article? a;
    try {
      a = await src.extract(settle: true);
    } catch (_) {
      a = null;
    }
    if (a == null) return null;
    final chunks = TextChunker.chunk('${a.title}. \n\n${a.text}');
    return chunks.isEmpty ? null : _Fresh(a, chunks);
  }

  void _applyFresh(_Fresh f, {required bool keepPosition}) {
    final old = currentChunk;
    _mapFuture = null;
    _stale = false;
    _error = null;
    _article = f.article;
    _baselineLen = f.article.domLength;
    if (f.article.url.isNotEmpty) _pageUrl = f.article.url;
    _chunks = f.chunks;
    final at = (keepPosition && old.isNotEmpty) ? f.chunks.indexOf(old) : -1;
    _index = at >= 0 ? at : 0;
  }

  /// Re-read the LIVE page without reloading it (see earlier notes).
  Future<void> refresh({bool keepPosition = true}) async {
    final src = _source;
    if (src == null || _disposed || _state == ReaderState.extracting) return;
    _autoTimer?.cancel();
    _cancelAdvance();

    final op = ++_opSeq;
    final prev = _state;
    final wasPlaying = prev == ReaderState.playing;

    _sessionToken++;
    _hlToken++;
    if (wasPlaying) {
      _state = ReaderState.extracting;
      _notify();
    }
    await _tts.stop();
    unawaited(src.clearHighlight());
    if (op != _opSeq || _disposed) return;

    await _rebuild(src, keepPosition: keepPosition);
    if (op != _opSeq || _disposed) return;

    if (!keepPosition) _index = 0;
    if (_chunks.isNotEmpty) _index = _index.clamp(0, _chunks.length - 1);

    var next = wasPlaying ? ReaderState.playing : prev;
    if (_chunks.isEmpty || next == ReaderState.error) next = ReaderState.idle;
    _state = next;
    _notify();
    if (_state == ReaderState.playing) unawaited(_run());
  }

  Future<void> restart() async {
    if (_source == null) return;
    if (_chunks.isEmpty) return loadPage(autoPlay: true, url: _pageUrl);
    await refresh(keepPosition: false);
  }

  Future<bool> _rebuild(PageContentSource src, {required bool keepPosition}) async {
    final my = ++_loadToken;
    final f = await _extractFresh(src);
    if (my != _loadToken || _disposed || !identical(src, _source)) return false;
    _mapFuture = null;
    _stale = false;
    if (f == null) return false;
    if (listEquals(f.chunks, _chunks)) {
      _article = f.article;
      _baselineLen = f.article.domLength;
      if (f.article.url.isNotEmpty) _pageUrl = f.article.url;
      return true; // unchanged: same list instance
    }
    _applyFresh(f, keepPosition: keepPosition);
    return true;
  }

  // ------------------------------------------------- SPA change detection
  void onContentChanged(int domLength) {
    if (_disposed || _source == null || _advancing || _state == ReaderState.extracting) {
      return;
    }
    final threshold = math.max(80, _baselineLen * 0.02);
    final material = _chunks.isEmpty || (domLength - _baselineLen).abs() >= threshold;
    if (!material) return;

    if (!_stale) {
      _stale = true;
      _notify();
    }
    if (isPlaying) return;

    _autoTimer?.cancel();
    final since = DateTime.now().difference(_lastAuto);
    final wait = since < autoRefreshMinGap ? autoRefreshMinGap - since : autoRefreshDelay;
    _autoTimer = Timer(wait, () {
      if (_disposed || isPlaying || _state == ReaderState.extracting) return;
      _lastAuto = DateTime.now();
      unawaited(refresh());
    });
  }

  void onRouteChanged(String url, {bool autoPlay = false}) {
    if (_disposed || _source == null || _advancing || _state == ReaderState.extracting) {
      return;
    }
    if (_sameDocument(url, _pageUrl)) return;
    _pageUrl = url;
    if (isPlaying) {
      _stale = true;
      _notify();
      return;
    }
    unawaited(_refreshForRoute(autoPlay));
  }

  Future<void> _refreshForRoute(bool autoPlay) async {
    final before = _chunks;
    await refresh();
    if (autoPlay && !_disposed && hasContent && !isPlaying && !identical(before, _chunks)) {
      await play();
    }
  }

  static bool _sameDocument(String a, String? b) {
    if (b == null) return false;
    final ua = Uri.tryParse(a), ub = Uri.tryParse(b);
    if (ua == null || ub == null) return a == b;
    return ua.removeFragment() == ub.removeFragment();
  }

  /// A real page load started (WebView onLoadStart).
  void onNavigationStarted() {
    if (_advancing) _navStarted = true;
  }

  // ------------------------------------------------------- chapter advance
  bool get _canAdvance =>
      _settings.autoNextChapter &&
      _source != null &&
      _rules?.match(_pageUrl ?? '') != null;

  void _cancelAdvance() {
    _advToken++;
    _advancing = false;
    _navStarted = false;
  }

  /// User pressed "next chapter" (button, notification, headset).
  Future<void> nextChapter() async {
    final src = _source;
    if (src == null || _disposed) return;
    if (_rules?.match(_pageUrl ?? '') == null) {
      _notice = ReaderNotice.of(NoticeKind.noRule);
      _notify();
      return;
    }
    final op = ++_opSeq;
    _cancelAdvance();
    _sessionToken++;
    _hlToken++;
    await _tts.stop();
    if (op != _opSeq || _disposed) return;
    unawaited(_advanceChapter());
  }

  void _failAdvance(NoticeKind kind, [String? reason]) {
    _advToken++;
    _advancing = false;
    _navStarted = false;
    _hlToken++;
    _state = ReaderState.idle; // auto-read STOPS
    _notice = ReaderNotice.of(kind, reason);
    _notify();
  }

  Future<void> _advanceChapter() async {
    final src = _source;
    final rule = _rules?.match(_pageUrl ?? '');
    if (src == null || rule == null) return;

    final token = ++_advToken;
    bool alive() => token == _advToken && !_disposed && identical(src, _source);

    _advancing = true;
    _navStarted = false;
    _advBeforeChunks = _chunks;
    _state = ReaderState.playing;
    _notice = null;
    _hlToken++;
    _notify();
    unawaited(src.clearHighlight());

    final before = await src.fingerprint();
    if (!alive()) return;

    final click = await src.clickElement(rule.selector);
    if (!alive()) return;
    switch (click.status) {
      case ClickStatus.notFound:
        return _failAdvance(NoticeKind.nextNotFound);
      case ClickStatus.notClickable:
        return _failAdvance(NoticeKind.nextNotClickable, click.reason);
      case ClickStatus.clicked:
        break;
    }

    // Wait for: (a) a real navigation -> loadPage() takes over, or
    // (b) the content changing in place (SPA) -> verify and apply here.
    final sw = Stopwatch()..start();
    var last = before;
    while (true) {
      await Future<void>.delayed(advancePoll);
      if (!alive()) return;

      final limit = _navStarted ? advanceLoadTimeout : advanceNoChangeTimeout;
      if (sw.elapsed > limit) {
        return _failAdvance(_navStarted ? NoticeKind.nextTimeout : NoticeKind.nextNoChange);
      }
      if (_navStarted) continue; // loadPage() will complete the hand-over

      final fp = await src.fingerprint();
      if (!alive()) return;
      if (fp == null || fp == last) continue;
      last = fp;
      if (before != null && fp == before) continue;

      // Looks changed. Give a navigation a moment to announce itself so we
      // don't race the WebView's own onLoadStop.
      await Future<void>.delayed(advancePoll);
      if (!alive()) return;
      if (_navStarted) continue;

      final fresh = await _extractFresh(src);
      if (!alive()) return;
      if (fresh == null) continue; // not readable yet
      if (listEquals(fresh.chunks, _advBeforeChunks)) continue; // cosmetic change

      _advancing = false;
      _applyFresh(fresh, keepPosition: false);
      _chaptersAdvanced++;
      _state = ReaderState.playing;
      _notify();
      unawaited(_run()); // auto-read the new chapter
      return;
    }
  }

  // ------------------------------------------------------------ transport
  Future<void> play() async {
    if (_chunks.isEmpty) return loadPage(autoPlay: true, url: _pageUrl);
    final op = ++_opSeq;
    await _tts.init();
    await _tts.setRate(_settings.speechRate);
    await _tts.setPitch(_settings.pitch);
    await _tts.setVolume(_settings.volume);
    await _tts.applyVoice(_settings.voiceName, _settings.voiceLocale);
    if (op != _opSeq || _disposed) return;
    _notice = null;
    _state = ReaderState.playing;
    _notify();
    unawaited(_run());
  }

  Future<void> pause() async {
    _opSeq++;
    _sessionToken++;
    _cancelAdvance();
    _state = ReaderState.paused;
    _notify();
    final ok = await _tts.pause();
    if (!ok) await _tts.stop();
  }

  Future<void> togglePlayPause() => isPlaying ? pause() : play();

  Future<void> stop() async {
    _opSeq++;
    _sessionToken++;
    _hlToken++;
    _cancelAdvance();
    _state = ReaderState.idle;
    _notify();
    await _tts.stop();
    await _source?.clearHighlight();
  }

  Future<void> next() => _jumpTo(_index + 1);
  Future<void> previous() => _jumpTo(_index - 1);
  Future<void> seekTo(int i) => _jumpTo(i);

  Future<void> _jumpTo(int i) async {
    if (_chunks.isEmpty) return;
    final op = ++_opSeq;
    _sessionToken++;
    _hlToken++;
    _cancelAdvance();
    await _tts.stop();
    if (op != _opSeq || _disposed) return;
    _index = i.clamp(0, _chunks.length - 1);
    _notify();
    if (_state == ReaderState.playing) unawaited(_run());
  }

  Future<void> _run() async {
    final token = ++_sessionToken;
    while (true) {
      if (token != _sessionToken || _disposed || _state != ReaderState.playing) return;
      final idx = _index;
      final text = currentChunk;
      if (text.isEmpty) return;

      unawaited(_highlight(idx, text));

      try {
        await _tts.speak(text);
      } catch (e) {
        if (token == _sessionToken && !_disposed) {
          _error = e.toString();
          _state = ReaderState.error;
          _notify();
        }
        return;
      }

      if (token != _sessionToken || _disposed || _state != ReaderState.playing) return;

      if (idx + 1 >= _chunks.length) {
        if (_canAdvance) {
          unawaited(_advanceChapter()); // keeps state == playing
          return;
        }
        _state = ReaderState.idle;
        _hlToken++;
        _notify();
        unawaited(_source?.clearHighlight() ?? Future.value());
        return;
      }
      _index = idx + 1;
      _notify();
    }
  }

  // ---------------------------------------------------------- highlighting
  Future<void> _highlight(int idx, String text) async {
    if (!_settings.highlightSentence) return;
    final src = _source;
    if (src == null) return;
    final t = ++_hlToken;
    try {
      final map = await (_mapFuture ??= src.snapshotTextNodes().then((n) => TextMap(n)));
      if (t != _hlToken || _disposed || !identical(src, _source)) return;
      final r = map.locateForIndex(idx, text);
      if (r == null) {
        await src.clearHighlight();
        return;
      }
      if (t != _hlToken || _disposed) return;
      final ok = await src.highlight(r);
      if (!ok) _mapFuture = null;
    } catch (_) {
      _mapFuture = null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionToken++;
    _loadToken++;
    _hlToken++;
    _opSeq++;
    _cancelAdvance();
    _autoTimer?.cancel();
    _tts.onError = null;
    unawaited(_tts.stop());
    unawaited(_source?.clearHighlight(release: true) ?? Future.value());
    _source = null;
    _webRef = null;
    _mapFuture = null;
    _chunks = const [];
    _article = null;
    super.dispose();
  }
}