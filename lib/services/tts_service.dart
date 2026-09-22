import 'dart:async';
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';

class TtsVoice {
  final String name;
  final String locale;
  const TtsVoice(this.name, this.locale);
  @override
  String toString() => '$name ($locale)';
}

class TtsService {
  final FlutterTts _tts = FlutterTts();

  VoidCallback? onComplete;
  void Function(String msg)? onError;
  void Function(int start, int end, String word)? onProgress;

  bool _initialised = false;

  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;

    // awaitSpeakCompletion is essential: without it, speak() returns
    // immediately and chunk sequencing breaks.
    await _tts.awaitSpeakCompletion(true);

    if (Platform.isAndroid) {
      await _tts.setQueueMode(0); // QUEUE_FLUSH
    }

    _tts.setCompletionHandler(() => onComplete?.call());
    _tts.setCancelHandler(() {});
    _tts.setErrorHandler((m) => onError?.call(m.toString()));
    _tts.setProgressHandler((text, start, end, word) {
      onProgress?.call(start, end, word);
    });
  }

  Future<List<TtsVoice>> voices() async {
    final raw = await _tts.getVoices;
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((v) => TtsVoice(
            (v['name'] ?? '').toString(), (v['locale'] ?? '').toString()))
        .where((v) => v.name.isNotEmpty)
        .toList()
      ..sort((a, b) => a.locale.compareTo(b.locale));
  }

  Future<void> applyVoice(String? name, String? locale) async {
    if (name == null || locale == null) return;
    try {
      await _tts.setVoice({'name': name, 'locale': locale});
    } catch (_) {/* voice uninstalled */}
  }

  Future<void> setRate(double v) => _tts.setSpeechRate(v);
  Future<void> setPitch(double v) => _tts.setPitch(v);
  Future<void> setVolume(double v) => _tts.setVolume(v);

  Future<void> speak(String text) => _tts.speak(text);
  Future<void> stop() => _tts.stop();

  /// Android pause works on API 26+. Returns false if unsupported,
  /// letting the controller fall back to stop+replay-from-chunk-start.
  Future<bool> pause() async {
    try {
      final r = await _tts.pause();
      return r == 1;
    } catch (_) {
      return false;
    }
  }

  Future<void> dispose() async {
    onComplete = null;
    onError = null;
    onProgress = null;
    // flutter_tts can't remove handlers, so replace them with no-ops
    // to release the closures (and whatever they captured).
    _tts.setCompletionHandler(() {});
    _tts.setCancelHandler(() {});
    _tts.setErrorHandler((_) {});
    _tts.setProgressHandler((a, b, c, d) {});
    try { await _tts.stop(); } catch (_) {}
  }
}

typedef VoidCallback = void Function();
