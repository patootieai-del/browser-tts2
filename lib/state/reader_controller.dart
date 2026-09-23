import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/utils/text_chunker.dart';
import '../core/utils/text_map.dart';
import '../models/article.dart';
import '../services/extraction_service.dart';
import '../services/settings_service.dart';
import '../services/speech_engine.dart';

enum ReaderState { idle, extracting, playing, paused, error }

/// INVARIANT: the chunk that is spoken, the chunk that is highlighted and
/// [index] are always the same chunk. (See token notes below.)
///
/// SPA SUPPORT: content can change without a page load. The chunks can be
/// rebuilt from the live page via [refresh] / [restart]; page-side DOM
/// changes arrive through [onContentChanged]; pushState navigations arrive
/// through [onRouteChanged]. Speech is never interrupted by *automatic*
/// detection, only by explicit user actions.
class ReaderController extends ChangeNotifier {
  ReaderController({
    required SpeechEngine tts,
    required ExtractionService extractor,
    this.autoRefreshDelay = const Duration(milliseconds: 1200),
    this.autoRefreshMinGap = const Duration(seconds: 5),
  })  : _tts = tts,
        _extractor = extractor {
    _tts.onError = (m) {
      if (_disposed) return;
      _sessionToken++;
      _error = m;
      _state = ReaderState.error;
      notifyListeners();
    };
  }

  final SpeechEngine _tts;
  final ExtractionService _extractor;
  final Duration autoRefreshDelay;
  final Duration autoRefreshMinGap;

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

  int _sessionToken = 0; // which playback loop/utterance is current
  int _loadToken = 0; // which extraction is current
  int _hlToken = 0; // which highlight request is current
  int _opSeq = 0; // serialises transport operations

  Article? get article => _article;
  List<String> get chunks => _chunks;
  int get index => _index;
  ReaderState get state => _state;
  String? get error => _error;
  bool get hasContent => _chunks.isNotEmpty;
  bool get isPlaying => _state == ReaderState.playing;
  bool get isStale => _stale;
  String get currentChunk =>
      (_index >= 0 && _index < _chunks.length) ? _chunks[_index] : '';
  double get progress => _chunks.isEmpty ? 0 : (_index + 1) / _chunks.length;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ------------------------------------------------------------- binding
  void bind(InAppWebViewController? c) {
    if (identical(c, _webRef)) return;
    _webRef = c;
    bindSource(c == null ? null : _extractor.forController(c));
  }

  /// Also used by tests to inject a fake page.
  void bindSource(PageContentSource? s) {
    _sessionToken++;
    _loadToken++;
    _hlToken++;
    _opSeq++;
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

    if (isPlaying && (rateChanged || pitchChanged || voiceChanged)) {
      _sessionToken++;
      await _tts.stop();
      if (isPlaying && !_disposed) unawaited(_run());
    }
  }

  // -------------------------------------------------------------- loading
  /// Full (re)load: a NEW page. Stops speech and resets position.
  Future<void> loadPage({bool autoPlay = false, String? url}) async {
    final src = _source;
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

    try {
      final a = await src.extract(settle: true);
      if (my != _loadToken || _disposed) return;
      if (a == null) {
        _state = ReaderState.idle;
        _error = 'No readable text found on this page.';
        _notify();
        return;
      }
      _article = a;
      _baselineLen = a.domLength;
      if (a.url.isNotEmpty) _pageUrl = a.url;
      _chunks = TextChunker.chunk('${a.title}. \n\n${a.text}');
      _state = ReaderState.idle;
      _notify();
      if (autoPlay && _chunks.isNotEmpty) await play();
    } catch (e) {
      if (my != _loadToken || _disposed) return;
      _error = e.toString();
      _state = ReaderState.error;
      _notify();
    }
  }

  /// Re-read the LIVE page and rebuild the chunks without reloading it.
  ///
  ///  * Unchanged content -> chunks are kept (same list instance).
  ///  * [keepPosition]: stay on the current sentence if it still exists in
  ///    the new content (e.g. content was appended); otherwise go to top.
  ///  * If it was playing, playback continues from the resulting position.
  Future<void> refresh({bool keepPosition = true}) async {
    final src = _source;
    if (src == null || _disposed || _state == ReaderState.extracting) return;
    _autoTimer?.cancel();

    final op = ++_opSeq;
    final prev = _state;
    final wasPlaying = prev == ReaderState.playing;

    _sessionToken++; // the running utterance/loop becomes stale
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

  /// Restart: re-check the page, rebuild if it changed, go to the top.
  Future<void> restart() async {
    if (_source == null) return;
    if (_chunks.isEmpty) return loadPage(autoPlay: true, url: _pageUrl);
    await refresh(keepPosition: false);
  }

  Future<bool> _rebuild(PageContentSource src,
      {required bool keepPosition}) async {
    final my = ++_loadToken;
    Article? a;
    try {
      a = await src.extract(settle: true);
    } catch (_) {
      a = null;
    }
    if (my != _loadToken || _disposed || !identical(src, _source)) return false;

    _mapFuture = null; // the DOM may have been re-rendered: new node ids
    _stale = false;
    if (a == null) return false;
    _baselineLen = a.domLength;
    if (a.url.isNotEmpty) _pageUrl = a.url;

    final fresh = TextChunker.chunk('${a.title}. \n\n${a.text}');
    if (fresh.isEmpty) return false;
    if (listEquals(fresh, _chunks)) {
      _article = a;
      return true; // unchanged: keep the very same list
    }
    final old = currentChunk;
    _article = a;
    _chunks = fresh;
    _error = null;
    final at = (keepPosition && old.isNotEmpty) ? fresh.indexOf(old) : -1;
    _index = at >= 0 ? at : 0;
    return true;
  }

  // ------------------------------------------------- SPA change detection
  /// The page reported DOM changes (debounced JS MutationObserver).
  void onContentChanged(int domLength) {
    if (_disposed || _source == null || _state == ReaderState.extracting) return;
    final threshold = math.max(80, _baselineLen * 0.02);
    final material = _chunks.isEmpty || (domLength - _baselineLen).abs() >= threshold;
    if (!material) return; // clocks, counters, carousels...

    if (!_stale) {
      _stale = true;
      _notify();
    }
    if (isPlaying) return; // never interrupt speech automatically

    _autoTimer?.cancel();
    final since = DateTime.now().difference(_lastAuto);
    final wait = since < autoRefreshMinGap
        ? autoRefreshMinGap - since
        : autoRefreshDelay;
    _autoTimer = Timer(wait, () {
      if (_disposed || isPlaying || _state == ReaderState.extracting) return;
      _lastAuto = DateTime.now();
      unawaited(refresh());
    });
  }

  /// URL changed without a page load (history.pushState etc.).
  void onRouteChanged(String url, {bool autoPlay = false}) {
    if (_disposed || _source == null || _state == ReaderState.extracting) return;
    if (_sameDocument(url, _pageUrl)) return; // fragment-only / same page
    _pageUrl = url;
    if (isPlaying) {
      _stale = true; // offer a refresh, don't cut the speech
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
    _state = ReaderState.playing;
    _notify();
    unawaited(_run());
  }

  Future<void> pause() async {
    _opSeq++;
    _sessionToken++;
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
    await _tts.stop();
    if (op != _opSeq || _disposed) return;
    _index = i.clamp(0, _chunks.length - 1);
    _notify();
    if (_state == ReaderState.playing) unawaited(_run());
  }

  Future<void> _run() async {
    final token = ++_sessionToken;
    while (true) {
      if (token != _sessionToken || _disposed || _state != ReaderState.playing) {
        return;
      }
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

      if (token != _sessionToken || _disposed || _state != ReaderState.playing) {
        return;
      }

      if (idx + 1 >= _chunks.length) {
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
      final map = await (_mapFuture ??=
          src.snapshotTextNodes().then((n) => TextMap(n)));
      if (t != _hlToken || _disposed || !identical(src, _source)) return;

      final r = map.locateForIndex(idx, text);
      if (r == null) {
        await src.clearHighlight(); // no confident match: show nothing
        return;
      }
      if (t != _hlToken || _disposed) return;
      final ok = await src.highlight(r);
      if (!ok) _mapFuture = null; // page re-rendered: re-snapshot next time
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