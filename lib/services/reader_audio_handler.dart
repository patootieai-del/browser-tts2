import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';

import '../state/reader_controller.dart';
import 'keep_awake.dart';

/// Bridges ReaderController <-> Android media session + foreground service.
/// The reader stays the single source of truth; this class only mirrors its
/// state and forwards commands.
class ReaderAudioHandler extends BaseAudioHandler {
  ReaderAudioHandler(this._reader, {KeepAwake? keepAwake})
      : _keepAwake = keepAwake ?? ChannelKeepAwake() {
    _reader.addListener(_sync);
    _sync();
  }

  final ReaderController _reader;
  final KeepAwake _keepAwake;
  final _subs = <StreamSubscription<Object?>>[];

  late final Future<AudioSession> _session = _initSession();
  bool _lastPlaying = false;
  bool _interrupted = false;
  String _lastKey = '';

  Future<AudioSession> _initSession() async {
    final s = await AudioSession.instance;
    await s.configure(const AudioSessionConfiguration.speech());
    _subs.add(s.interruptionEventStream.listen(_onInterruption));
    _subs.add(s.becomingNoisyEventStream.listen((_) => _reader.pause()));
    return s;
  }

  void _onInterruption(AudioInterruptionEvent e) {
    if (e.begin) {
      if (_reader.isPlaying) {
        _interrupted = true; // phone call, another media app...
        _reader.pause();
      }
    } else if (_interrupted) {
      _interrupted = false;
      _reader.play();
    }
  }

  // ------------------------------------------------- reader -> system
  void _sync() {
    final r = _reader;
    final playing = r.isPlaying;
    final processing = r.state == ReaderState.extracting
        ? AudioProcessingState.loading
        : (r.hasContent || playing)
            ? AudioProcessingState.ready
            : AudioProcessingState.idle;

    final a = r.article;
    final notice = r.notice;
    final title = (a?.title.isNotEmpty ?? false) ? a!.title : 'Vox Browser';
    final artist = notice != null
        ? 'Stopped: ${notice.shortText}'
        : r.isAdvancing
            ? 'Loading next chapter…'
            : (Uri.tryParse(a?.url ?? '')?.host ?? '');
    final id = a?.url ?? 'none';
    final cur = mediaItem.value;
    if (cur == null || cur.id != id || cur.title != title || cur.artist != artist) {
      mediaItem.add(MediaItem(id: id, title: title, artist: artist));
    }

    final key = '$playing|$processing';
    if (key != _lastKey) {
      _lastKey = key;
      playbackState.add(PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          playing ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl.fastForward, // = next chapter
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.play,
          MediaAction.pause,
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,
          MediaAction.fastForward,
          MediaAction.stop,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: processing,
        playing: playing,
      ));
    }

    if (playing != _lastPlaying) {
      _lastPlaying = playing;
      unawaited(_onPlayingChanged(playing));
    }
  }

  Future<void> _onPlayingChanged(bool playing) async {
    final session = await _session;
    if (playing) {
      await _keepAwake.acquire(); // CPU + Wi-Fi stay up with the screen off
      if (!await session.setActive(true)) {
        await _reader.pause(); // focus denied (e.g. during a call)
      }
    } else {
      await _keepAwake.release();
      if (!_interrupted) await session.setActive(false);
    }
  }

  // ------------------------------------------------- system -> reader
  @override
  Future<void> play() => _reader.play();
  @override
  Future<void> pause() => _reader.pause();
  @override
  Future<void> skipToNext() => _reader.next();
  @override
  Future<void> skipToPrevious() => _reader.previous();
  @override
  Future<void> fastForward() => _reader.nextChapter();

  @override
  Future<void> stop() async {
    await _reader.stop();
    await _keepAwake.release();
    _lastKey = '';
    await super.stop(); // ends the foreground service
  }

  @override
  Future<void> onTaskRemoved() => stop(); // user swiped the app away

  Future<void> dispose() async {
    _reader.removeListener(_sync);
    for (final s in _subs) {
      await s.cancel();
    }
    await _keepAwake.release();
  }
}