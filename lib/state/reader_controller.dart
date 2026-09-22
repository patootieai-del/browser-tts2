import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/utils/text_chunker.dart';
import '../models/article.dart';
import '../services/extraction_service.dart';
import '../services/settings_service.dart';
import '../services/tts_service.dart';

enum ReaderState { idle, extracting, playing, paused, error }

class ReaderController extends ChangeNotifier {
  ReaderController({
    required TtsService tts,
    required ExtractionService extractor,
  })  : _tts = tts,
        _extractor = extractor {
    _tts.onComplete = _handleChunkComplete;
    _tts.onError = (m) {
      if (_disposed) return;
      _error = m;
      _state = ReaderState.error;
      notifyListeners();
    };
  }

  final TtsService _tts;
  final ExtractionService _extractor;

  InAppWebViewController? _web;
  AppSettings _settings = const AppSettings();

  Article? _article;
  List<String> _chunks = const [];
  int _index = 0;
  ReaderState _state = ReaderState.idle;
  String? _error;
  bool _disposed = false;

  int _sessionToken = 0; // invalidates stale TTS callbacks
  int _loadToken = 0;    // invalidates stale extractions

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

  /// Bind to the active tab's WebView (or null). Stops speech and drops the
  /// previous page's text so no dead controller or big string is retained.
  void bind(InAppWebViewController? c) {
    if (identical(c, _web)) return;
    _sessionToken++;
    _loadToken++;
    unawaited(_tts.stop());
    _web = c;
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
      await _speakCurrent();
    }
  }

  Future<void> loadPage({bool autoPlay = false}) async {
    final c = _web;
    final my = ++_loadToken;
    _sessionToken++;
    await _tts.stop();
    _article = null;
    _chunks = const [];
    _index = 0;
    _error = null;
    _state = ReaderState.extracting;
    _notify();

    if (c == null) {
      _state = ReaderState.idle;
      _notify();
      return;
    }

    try {
      final a = await _extractor.extract(c);
      // Tab switched / page changed while extracting? Discard the result.
      if (my != _loadToken || _disposed) return;
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
    await _tts.init();
    await _tts.setRate(_settings.speechRate);
    await _tts.setPitch(_settings.pitch);
    await _tts.setVolume(_settings.volume);
    await _tts.applyVoice(_settings.voiceName, _settings.voiceLocale);
    _state = ReaderState.playing;
    _notify();
    await _speakCurrent();
  }

  Future<void> pause() async {
    _sessionToken++;
    final ok = await _tts.pause();
    if (!ok) await _tts.stop(); // resume restarts the current chunk
    _state = ReaderState.paused;
    _notify();
  }

  Future<void> togglePlayPause() => isPlaying ? pause() : play();

  Future<void> stop() async {
    _sessionToken++;
    await _tts.stop();
    _state = ReaderState.idle;
    final c = _web;
    if (c != null) await _extractor.clearHighlight(c);
    _notify();
  }

  Future<void> next() => _jumpTo(_index + 1);
  Future<void> previous() => _jumpTo(_index - 1);
  Future<void> restart() => _jumpTo(0);
  Future<void> seekTo(int i) => _jumpTo(i);

  Future<void> _jumpTo(int i) async {
    if (_chunks.isEmpty) return;
    _sessionToken++;
    await _tts.stop();
    _index = i.clamp(0, _chunks.length - 1);
    _notify();
    if (_state == ReaderState.playing) await _speakCurrent();
  }

  Future<void> _speakCurrent() async {
    final text = currentChunk;
    if (text.isEmpty) return;
    ++_sessionToken;
    final c = _web;
    if (_settings.highlightSentence && c != null) {
      unawaited(_extractor.highlight(c, text));
    }
    await _tts.speak(text);
  }

  void _handleChunkComplete() {
    if (_disposed || _state != ReaderState.playing) return;
    if (_index + 1 >= _chunks.length) {
      _state = ReaderState.idle;
      _index = _chunks.length - 1;
      _notify();
      return;
    }
    _index++;
    _notify();
    _speakCurrent();
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionToken++;
    _loadToken++;
    _tts.onComplete = null;
    _tts.onError = null;
    unawaited(_tts.stop());
    _web = null;
    _chunks = const [];
    _article = null;
    super.dispose();
  }
}