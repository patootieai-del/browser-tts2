import 'dart:async';

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
/// [index] are always the same chunk.
///
///  * [_index] changes only (a) inside the token-guarded [_run] loop, or
///    (b) in [_jumpTo] / [bindSource] / [loadPage].
///  * Every utterance and its highlight request are created from the same
///    captured (idx, text) pair.
///  * Completion of any utterance that is not the current one is ignored
///    (_sessionToken), and stale highlight requests are dropped (_hlToken).
class ReaderController extends ChangeNotifier {
  ReaderController({
    required SpeechEngine tts,
    required ExtractionService extractor,
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

  int _sessionToken = 0; // which playback loop/utterance is current
  int _loadToken = 0; // which page extraction is current
  int _hlToken = 0; // which highlight request is current
  int _opSeq = 0; // serialises transport operations

  Article? get article => _article;
  List<String> get chunks => _chunks;
  int get index => _index;
  ReaderState get state => _state;
  String? get error => _error;
  bool get hasContent => _chunks.isNotEmpty;
  bool get isPlaying => _state == ReaderState.playing;
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
    unawaited(_tts.stop());
    final old = _source;
    if (old != null) unawaited(old.clearHighlight(release: true));
    _source = s;
    _mapFuture = null;
    _article = null;
    _chunks = const [];
    _index = 0;
    _error = null;
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
  Future<void> loadPage({bool autoPlay = false}) async {
    final src = _source;
    final my = ++_loadToken;
    _sessionToken++;
    _hlToken++;
    _opSeq++;
    _mapFuture = null;
    _article = null;
    _chunks = const [];
    _index = 0;
    _error = null;
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
      final a = await src.extract();
      if (my != _loadToken || _disposed) return; // tab/page changed
      if (a == null) {
        _state = ReaderState.idle;
        _error = 'No readable text found on this page.';
        _notify();
        return;
      }
      _article = a;
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

  // ------------------------------------------------------------ transport
  Future<void> play() async {
    if (_chunks.isEmpty) return loadPage(autoPlay: true);
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
    _sessionToken++; // current utterance's completion becomes stale
    _state = ReaderState.paused;
    _notify();
    final ok = await _tts.pause();
    if (!ok) await _tts.stop(); // resume re-speaks the current chunk
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
  Future<void> restart() => _jumpTo(0);
  Future<void> seekTo(int i) => _jumpTo(i);

  Future<void> _jumpTo(int i) async {
    if (_chunks.isEmpty) return;
    final op = ++_opSeq;
    _sessionToken++; // kills the running loop immediately
    _hlToken++;
    await _tts.stop();
    if (op != _opSeq || _disposed) return; // a newer operation took over
    _index = i.clamp(0, _chunks.length - 1);
    _notify();
    if (_state == ReaderState.playing) unawaited(_run());
  }

  /// The one and only playback loop. Speaks chunk after chunk until the end
  /// or until its token is invalidated by any transport operation.
  Future<void> _run() async {
    final token = ++_sessionToken;
    while (true) {
      if (token != _sessionToken || _disposed || _state != ReaderState.playing) {
        return;
      }
      // Capture once: what we speak is exactly what we highlight.
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

      // A cancelled / superseded utterance may complete late: ignore it.
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
        // No confident match: show nothing rather than something wrong.
        await src.clearHighlight();
        return;
      }
      if (t != _hlToken || _disposed) return;
      await src.highlight(r);
    } catch (_) {
      _mapFuture = null; // allow a retry next time
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionToken++;
    _loadToken++;
    _hlToken++;
    _opSeq++;
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