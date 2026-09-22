class AppConfig {
  static const homeUrl = 'https://duckduckgo.com';

  /// WebViews kept alive at once (active tab + most recently used).
  static const maxLiveTabs = 3;

  /// Hard cap on tabs; the oldest background tab is closed beyond this.
  static const maxTabs = 30;

  /// Android has one cookie jar. If true, cookies are wiped when the last
  /// incognito tab closes, which also logs you out of normal tabs.
  static const wipeCookiesWhenLastIncognitoTabCloses = false;
}