import 'package:shared_preferences/shared_preferences.dart';

enum ThemeChoice { system, light, dark, midnight, sepia, dracula, oled }

class AppSettings {
  final ThemeChoice theme;
  final bool useDynamicColor;
  final double speechRate;   // 0.2 – 1.5 (flutter_tts android scale)
  final double pitch;        // 0.5 – 2.0
  final double volume;       // 0.0 – 1.0
  final String? voiceName;
  final String? voiceLocale;
  final bool highlightSentence;
  final bool autoReadOnLoad;
  final bool keepScreenOn;
  final String searchEngine; // template with %s
  final double textScale;

  const AppSettings({
    this.theme = ThemeChoice.system,
    this.useDynamicColor = true,
    this.speechRate = 0.5,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.voiceName,
    this.voiceLocale,
    this.highlightSentence = true,
    this.autoReadOnLoad = false,
    this.keepScreenOn = true,
    this.searchEngine = 'https://duckduckgo.com/?q=%s',
    this.textScale = 1.0,
  });

  AppSettings copyWith({
    ThemeChoice? theme,
    bool? useDynamicColor,
    double? speechRate,
    double? pitch,
    double? volume,
    String? voiceName,
    String? voiceLocale,
    bool? highlightSentence,
    bool? autoReadOnLoad,
    bool? keepScreenOn,
    String? searchEngine,
    double? textScale,
  }) =>
      AppSettings(
        theme: theme ?? this.theme,
        useDynamicColor: useDynamicColor ?? this.useDynamicColor,
        speechRate: speechRate ?? this.speechRate,
        pitch: pitch ?? this.pitch,
        volume: volume ?? this.volume,
        voiceName: voiceName ?? this.voiceName,
        voiceLocale: voiceLocale ?? this.voiceLocale,
        highlightSentence: highlightSentence ?? this.highlightSentence,
        autoReadOnLoad: autoReadOnLoad ?? this.autoReadOnLoad,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
        searchEngine: searchEngine ?? this.searchEngine,
        textScale: textScale ?? this.textScale,
      );
}

class SettingsService {
  static const _kTheme = 'theme';
  static const _kDynamic = 'dynamic_color';
  static const _kRate = 'rate';
  static const _kPitch = 'pitch';
  static const _kVolume = 'volume';
  static const _kVoice = 'voice_name';
  static const _kVoiceLocale = 'voice_locale';
  static const _kHighlight = 'highlight';
  static const _kAutoRead = 'auto_read';
  static const _kKeepOn = 'keep_screen_on';
  static const _kEngine = 'search_engine';
  static const _kScale = 'text_scale';

  Future<AppSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return AppSettings(
      theme: ThemeChoice.values[p.getInt(_kTheme) ?? 0],
      useDynamicColor: p.getBool(_kDynamic) ?? true,
      speechRate: p.getDouble(_kRate) ?? 0.5,
      pitch: p.getDouble(_kPitch) ?? 1.0,
      volume: p.getDouble(_kVolume) ?? 1.0,
      voiceName: p.getString(_kVoice),
      voiceLocale: p.getString(_kVoiceLocale),
      highlightSentence: p.getBool(_kHighlight) ?? true,
      autoReadOnLoad: p.getBool(_kAutoRead) ?? false,
      keepScreenOn: p.getBool(_kKeepOn) ?? true,
      searchEngine:
          p.getString(_kEngine) ?? 'https://duckduckgo.com/?q=%s',
      textScale: p.getDouble(_kScale) ?? 1.0,
    );
  }

  Future<void> save(AppSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kTheme, s.theme.index);
    await p.setBool(_kDynamic, s.useDynamicColor);
    await p.setDouble(_kRate, s.speechRate);
    await p.setDouble(_kPitch, s.pitch);
    await p.setDouble(_kVolume, s.volume);
    await p.setBool(_kHighlight, s.highlightSentence);
    await p.setBool(_kAutoRead, s.autoReadOnLoad);
    await p.setBool(_kKeepOn, s.keepScreenOn);
    await p.setString(_kEngine, s.searchEngine);
    await p.setDouble(_kScale, s.textScale);
    if (s.voiceName != null) await p.setString(_kVoice, s.voiceName!);
    if (s.voiceLocale != null) {
      await p.setString(_kVoiceLocale, s.voiceLocale!);
    }
  }
}
