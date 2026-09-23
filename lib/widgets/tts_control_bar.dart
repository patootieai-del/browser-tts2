import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/reader_controller.dart';
import '../state/settings_controller.dart';

class TtsControlBar extends StatelessWidget {
  const TtsControlBar({
    super.key,
    required this.canGoBack,
    required this.canGoForward,
    required this.onWebBack,
    required this.onWebForward,
  });

  final bool canGoBack;
  final bool canGoForward;
  final VoidCallback onWebBack;
  final VoidCallback onWebForward;

  @override
  Widget build(BuildContext context) {
    final r = context.watch<ReaderController>();
    final cs = Theme.of(context).colorScheme;
    final busy = r.state == ReaderState.extracting;

    return Material(
      color: cs.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (r.isStale)
              InkWell(
                onTap: () => r.refresh(),
                child: Container(
                  width: double.infinity,
                  color: cs.tertiaryContainer,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(children: [
                    Icon(Icons.sync, size: 16, color: cs.onTertiaryContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          'Page content changed. Tap to refresh reading.',
                          style: TextStyle(
                              fontSize: 12, color: cs.onTertiaryContainer)),
                    ),
                  ]),
                ),
              ),
            if (r.isAdvancing)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Loading next chapter…'),
                ]),
              ),
            if (r.hasContent)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Text('${r.index + 1}',
                        style: Theme.of(context).textTheme.labelSmall),
                    Expanded(
                      child: Slider(
                        value: r.index.toDouble(),
                        min: 0,
                        max: (r.chunks.length - 1).toDouble().clamp(0, 1e9),
                        onChanged: (v) => r.seekTo(v.round()),
                      ),
                    ),
                    Text('${r.chunks.length}',
                        style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: 'Page back',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: canGoBack ? onWebBack : null,
                ),
                IconButton(
                  tooltip: 'Restart (re-reads the page)',
                  icon: const Icon(Icons.replay),
                  onPressed: r.hasContent ? r.restart : null,
                ),
                IconButton(
                  tooltip: 'Previous sentence',
                  icon: const Icon(Icons.skip_previous),
                  onPressed: r.hasContent ? r.previous : null,
                ),
                _PlayButton(
                    busy: busy, playing: r.isPlaying, onTap: r.togglePlayPause),
                IconButton(
                  tooltip: 'Next sentence',
                  icon: const Icon(Icons.skip_next),
                  onPressed: r.hasContent ? r.next : null,
                ),
                IconButton(
                  tooltip: 'Next chapter',
                  icon: const Icon(Icons.keyboard_double_arrow_right),
                  onPressed: r.isAdvancing ? null : r.nextChapter,
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (v) {
                    if (v == 'speed') _showSpeedSheet(context);
                    if (v == 'forward' && canGoForward) onWebForward();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'speed', child: Text('Speed & pitch')),
                    PopupMenuItem(
                        value: 'forward',
                        enabled: canGoForward,
                        child: const Text('Page forward')),
                  ],
                ),
                IconButton(
                  tooltip: 'Speed',
                  icon: const Icon(Icons.speed),
                  onPressed: () => _showSpeedSheet(context),
                ),
                IconButton(
                  tooltip: 'Page forward',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: canGoForward ? onWebForward : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showSpeedSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Consumer<SettingsController>(
        builder: (ctx, sc, _) {
          final s = sc.settings;
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Speech rate  ×${(s.speechRate * 2).toStringAsFixed(2)}'),
                Slider(
                  value: s.speechRate,
                  min: 0.1,
                  max: 1.5,
                  divisions: 28,
                  onChanged: (v) async {
                    await sc.update(s.copyWith(speechRate: v));
                    await ctx
                        .read<ReaderController>()
                        .applySettings(sc.settings);
                  },
                ),
                Text('Pitch  ${s.pitch.toStringAsFixed(2)}'),
                Slider(
                  value: s.pitch,
                  min: 0.5,
                  max: 2.0,
                  divisions: 30,
                  onChanged: (v) async {
                    await sc.update(s.copyWith(pitch: v));
                    await ctx
                        .read<ReaderController>()
                        .applySettings(sc.settings);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton(
      {required this.busy, required this.playing, required this.onTap});
  final bool busy;
  final bool playing;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 56,
      height: 56,
      child: busy
          ? const Center(
              child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2)))
          : FloatingActionButton(
              heroTag: 'tts-play',
              elevation: 1,
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              onPressed: onTap,
              child: Icon(playing ? Icons.pause : Icons.play_arrow, size: 30),
            ),
    );
  }
}
