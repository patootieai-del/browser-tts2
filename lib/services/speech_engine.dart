/// What ReaderController needs from a TTS engine. Lets tests inject a fake.
abstract class SpeechEngine {
  void Function(String message)? onError;

  Future<void> init();

  /// Completes when the utterance finishes OR is cancelled (Android engines
  /// may complete cancelled utterances late). Callers must not treat
  /// completion as "finished naturally" without their own token check.
  Future<void> speak(String text);

  Future<void> stop();
  Future<bool> pause();
  Future<void> setRate(double v);
  Future<void> setPitch(double v);
  Future<void> setVolume(double v);
  Future<void> applyVoice(String? name, String? locale);
}