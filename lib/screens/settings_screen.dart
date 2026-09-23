import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_themes.dart';
import '../services/keep_awake.dart';
import '../services/settings_service.dart';
import '../services/tts_service.dart';
import '../state/chapter_rule_store.dart';
import '../state/reader_controller.dart';
import '../state/settings_controller.dart';
import 'chapter_rules_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  List<TtsVoice> _voices = [];

  @override
  void initState() {
    super.initState();
    _loadVoices();
  }

  Future<void> _loadVoices() async {
    final v = await context.read<TtsService>().voices();
    if (mounted) setState(() => _voices = v);
  }

  @override
  Widget build(BuildContext context) {
    final sc = context.watch<SettingsController>();
    final s = sc.settings;

    Future<void> apply(AppSettings next) async {
      await sc.update(next);
      await context.read<ReaderController>().applySettings(next);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Appearance'),
          ...AppThemes.specs.entries.map((e) => RadioListTile<ThemeChoice>(
                value: e.key,
                groupValue: s.theme,
                title: Text(e.value.label),
                secondary: Icon(e.value.icon),
                onChanged: (v) => apply(s.copyWith(theme: v)),
              )),
          SwitchListTile(
            title: const Text('Material You dynamic colour'),
            subtitle: const Text('Android 12+, applies to "Follow system"'),
            value: s.useDynamicColor,
            onChanged: (v) => apply(s.copyWith(useDynamicColor: v)),
          ),
          ListTile(
            title: const Text('Text size'),
            subtitle: Slider(
              value: s.textScale,
              min: 0.8,
              max: 1.6,
              divisions: 8,
              label: '${(s.textScale * 100).round()}%',
              onChanged: (v) => apply(s.copyWith(textScale: v)),
            ),
          ),
          const _SectionHeader('Speech'),
          ListTile(
            title: const Text('Speech rate'),
            subtitle: Slider(
              value: s.speechRate,
              min: 0.1,
              max: 1.5,
              divisions: 28,
              label: s.speechRate.toStringAsFixed(2),
              onChanged: (v) => apply(s.copyWith(speechRate: v)),
            ),
          ),
          ListTile(
            title: const Text('Pitch'),
            subtitle: Slider(
              value: s.pitch,
              min: 0.5,
              max: 2.0,
              divisions: 30,
              label: s.pitch.toStringAsFixed(2),
              onChanged: (v) => apply(s.copyWith(pitch: v)),
            ),
          ),
          ListTile(
            title: const Text('Volume'),
            subtitle: Slider(
              value: s.volume,
              min: 0,
              max: 1,
              divisions: 10,
              onChanged: (v) => apply(s.copyWith(volume: v)),
            ),
          ),
          ListTile(
            title: const Text('Voice'),
            subtitle: Text(s.voiceName ?? 'Device default'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _voices.isEmpty
                ? null
                : () async {
                    final picked = await showModalBottomSheet<TtsVoice>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => DraggableScrollableSheet(
                        expand: false,
                        builder: (_, ctrl) => ListView.builder(
                          controller: ctrl,
                          itemCount: _voices.length,
                          itemBuilder: (_, i) => ListTile(
                            title: Text(_voices[i].name),
                            subtitle: Text(_voices[i].locale),
                            selected: _voices[i].name == s.voiceName,
                            onTap: () => Navigator.pop(context, _voices[i]),
                          ),
                        ),
                      ),
                    );
                    if (picked != null) {
                      await apply(s.copyWith(
                          voiceName: picked.name, voiceLocale: picked.locale));
                    }
                  },
          ),
          const _SectionHeader('Reading across chapters'),
          SwitchListTile(
            title: const Text('Auto-advance to next chapter'),
            subtitle: const Text(
                'When a chapter ends, tap the saved "next" button and keep reading'),
            value: s.autoNextChapter,
            onChanged: (v) => apply(s.copyWith(autoNextChapter: v)),
          ),
          ListTile(
            title: const Text('Saved next-chapter buttons'),
            subtitle:
                Text('${context.watch<ChapterRuleStore>().rules.length} saved'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const ChapterRulesScreen())),
          ),
          const _SectionHeader('Background reading'),
          ListTile(
            title: const Text('Allow unrestricted battery use'),
            subtitle: const Text(
                'Stops Android from ending long reading sessions with the screen off'),
            onTap: () async {
              final ok = await BackgroundSetup.requestUnrestrictedBattery();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(
                      ok ? 'Battery use is unrestricted' : 'Not changed')));
            },
          ),
          SwitchListTile(
            title: const Text('Highlight sentence being read'),
            value: s.highlightSentence,
            onChanged: (v) => apply(s.copyWith(highlightSentence: v)),
          ),
          SwitchListTile(
            title: const Text('Auto-read when a page loads'),
            value: s.autoReadOnLoad,
            onChanged: (v) => apply(s.copyWith(autoReadOnLoad: v)),
          ),
          const _SectionHeader('Browsing'),
          ListTile(
            title: const Text('Search engine'),
            subtitle: Text(Uri.parse(s.searchEngine).host),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              const engines = {
                'DuckDuckGo': 'https://duckduckgo.com/?q=%s',
                'Google': 'https://www.google.com/search?q=%s',
                'Bing': 'https://www.bing.com/search?q=%s',
                'Startpage': 'https://www.startpage.com/sp/search?query=%s',
              };
              final picked = await showDialog<String>(
                context: context,
                builder: (_) => SimpleDialog(
                  title: const Text('Search engine'),
                  children: engines.entries
                      .map((e) => SimpleDialogOption(
                            onPressed: () => Navigator.pop(context, e.value),
                            child: Text(e.key),
                          ))
                      .toList(),
                ),
              );
              if (picked != null) apply(s.copyWith(searchEngine: picked));
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold)),
      );
}
