enum BrowserCookieSource {
  chrome('Chrome', 'chrome', mayPromptForKeychain: true),
  safari('Safari', 'safari'),
  firefox('Firefox', 'firefox'),
  edge('Edge', 'edge', mayPromptForKeychain: true),
  brave('Brave', 'brave', mayPromptForKeychain: true),
  chromium('Chromium', 'chromium', mayPromptForKeychain: true),
  vivaldi('Vivaldi', 'vivaldi', mayPromptForKeychain: true),
  opera('Opera', 'opera', mayPromptForKeychain: true);

  const BrowserCookieSource(
    this.label,
    this.argumentValue, {
    this.mayPromptForKeychain = false,
  });

  final String label;
  final String argumentValue;
  final bool mayPromptForKeychain;

  static BrowserCookieSource? byName(String? name) {
    if (name == null) return null;
    for (final source in values) {
      if (source.name == name) return source;
    }
    return null;
  }
}

class YtDlpAuthentication {
  const YtDlpAuthentication({
    this.useBrowserCookies = false,
    this.browser = BrowserCookieSource.chrome,
    this.browserProfile,
  });

  final bool useBrowserCookies;
  final BrowserCookieSource browser;
  final String? browserProfile;

  static const none = YtDlpAuthentication();

  List<String> get arguments {
    if (!useBrowserCookies) return const [];
    return ['--cookies-from-browser', browserCookieArgument];
  }

  String get browserCookieArgument {
    final profile = browserProfile?.trim();
    if (profile == null || profile.isEmpty) return browser.argumentValue;
    return '${browser.argumentValue}:$profile';
  }

  YtDlpAuthentication copyWith({
    bool? useBrowserCookies,
    BrowserCookieSource? browser,
    String? browserProfile,
    bool clearBrowserProfile = false,
  }) {
    return YtDlpAuthentication(
      useBrowserCookies: useBrowserCookies ?? this.useBrowserCookies,
      browser: browser ?? this.browser,
      browserProfile: clearBrowserProfile
          ? null
          : browserProfile ?? this.browserProfile,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is YtDlpAuthentication &&
        other.useBrowserCookies == useBrowserCookies &&
        other.browser == browser &&
        other.browserProfile == browserProfile;
  }

  @override
  int get hashCode => Object.hash(useBrowserCookies, browser, browserProfile);
}
