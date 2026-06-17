import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/models/download_models.dart';
import 'package:yt_dlp_desktop/services/yt_dlp/yt_dlp_authentication.dart';
import 'package:yt_dlp_desktop/services/yt_dlp/yt_dlp_service.dart';

void main() {
  test('parses yt-dlp progress template lines', () {
    final progress = DownloadProgressParser.parse(
      'fetchdeck:downloading|42.5%|1.2MiB/s|00:12',
    );

    expect(progress, isNotNull);
    expect(progress!.status, 'downloading');
    expect(progress.percent, 42.5);
    expect(progress.speed, '1.2MiB/s');
    expect(progress.eta, '00:12');
    expect(progress.label, '42.5% • 1.2MiB/s • ETA 00:12');
  });

  test('parses yt-dlp final output path lines', () {
    final path = DownloadOutputParser.parse(
      'fetchdeck-file:/tmp/Fetchdeck/example.mp3',
    );

    expect(path, '/tmp/Fetchdeck/example.mp3');
  });

  test('browser cookie authentication builds yt-dlp arguments', () {
    const authentication = YtDlpAuthentication(
      useBrowserCookies: true,
      browser: BrowserCookieSource.safari,
    );

    expect(authentication.arguments, ['--cookies-from-browser', 'safari']);
    expect(YtDlpAuthentication.none.arguments, isEmpty);
    expect(BrowserCookieSource.chrome.mayPromptForKeychain, isTrue);
    expect(BrowserCookieSource.safari.mayPromptForKeychain, isFalse);
  });

  test('browser cookie authentication supports profiles', () {
    const authentication = YtDlpAuthentication(
      useBrowserCookies: true,
      browser: BrowserCookieSource.chrome,
      browserProfile: 'Profile 1',
    );

    expect(authentication.arguments, [
      '--cookies-from-browser',
      'chrome:Profile 1',
    ]);
  });

  test('download command uses documented mp3 selector and playlist intent', () {
    final singleVideoArguments = YtDlpService.buildDownloadArguments(
      url: 'https://youtube.com/watch?v=abc&list=playlist',
      preset: PresetDefinition.defaultPreset,
      outputDirectory: '/tmp/Fetchdeck',
      isPlaylist: false,
    );
    final playlistArguments = YtDlpService.buildDownloadArguments(
      url: 'https://youtube.com/playlist?list=playlist',
      preset: PresetDefinition.defaultPreset,
      outputDirectory: '/tmp/Fetchdeck',
      isPlaylist: true,
    );

    expect(singleVideoArguments, contains('--no-playlist'));
    expect(singleVideoArguments, isNot(contains('--yes-playlist')));
    expect(singleVideoArguments, contains('ba[acodec^=mp3]/ba/b'));
    expect(singleVideoArguments, contains('%(title).200B.%(ext)s'));
    expect(
      singleVideoArguments.any((value) => value.contains('%(id)s')),
      isFalse,
    );
    expect(playlistArguments, contains('--yes-playlist'));
    expect(playlistArguments, contains('--no-abort-on-error'));
    expect(playlistArguments, isNot(contains('--ignore-errors')));
    expect(
      playlistArguments,
      contains('%(playlist_index)03d - %(title).200B.%(ext)s'),
    );
    expect(playlistArguments.any((value) => value.contains('%(id)s')), isFalse);
  });

  test('parses playlist entries from yt-dlp json', () {
    final mediaInfo = MediaInfoParser.fromJson({
      'title': 'Road Trip Mix',
      'webpage_url': 'https://youtube.com/playlist?list=abc',
      'extractor_key': 'Youtube',
      'entries': [
        {
          'id': 'video-1',
          'title': 'First Song',
          'webpage_url': 'https://youtube.com/watch?v=video-1',
          'extractor_key': 'Youtube',
          'uploader': 'DJ Example',
          'thumbnail': 'https://example.com/one.jpg',
          'duration': 181,
          'playlist_index': 1,
        },
        {
          'id': 'video-2',
          'title': 'Second Song',
          'url': 'https://youtube.com/watch?v=video-2',
          'duration': '205',
        },
      ],
    }, fallbackUrl: 'https://youtube.com/playlist?list=abc');

    expect(mediaInfo.isPlaylist, isTrue);
    expect(mediaInfo.playlistCount, 2);
    expect(mediaInfo.entries, hasLength(2));
    expect(mediaInfo.entries.first.title, 'First Song');
    expect(mediaInfo.entries.first.duration, const Duration(seconds: 181));
    expect(mediaInfo.entries.first.playlistIndex, 1);
    expect(mediaInfo.entries.last.webpageUrl, contains('video-2'));
  });

  test('parses chapters from yt-dlp json', () {
    final mediaInfo = MediaInfoParser.fromJson({
      'title': 'Full Concert',
      'webpage_url': 'https://youtube.com/watch?v=concert',
      'extractor_key': 'Youtube',
      'duration': 7200,
      'chapters': [
        {'title': 'Opening', 'start_time': 0, 'end_time': 95.2},
        {'title': 'Main Song', 'start_time': '95', 'end_time': '240'},
        {'title': 'Broken', 'start_time': 250, 'end_time': 250},
      ],
    }, fallbackUrl: 'https://youtube.com/watch?v=concert');

    expect(mediaInfo.isPlaylist, isFalse);
    expect(mediaInfo.hasChapters, isTrue);
    expect(mediaInfo.chapters, hasLength(2));
    expect(mediaInfo.chapters.first.title, 'Opening');
    expect(mediaInfo.chapters.first.duration, const Duration(seconds: 95));
    expect(mediaInfo.chapters.last.startTime, const Duration(seconds: 95));
  });

  test('explains macOS Safari cookie permission errors', () {
    final message = YtDlpErrorCleaner.clean(
      "[Errno 1] Operation not permitted: '/Users/marko/Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies'",
    );

    expect(message, contains('macOS blocked access to Safari cookies'));
    expect(message, contains('Full Disk Access'));
  });

  test('explains private playlist entries without downloadable formats', () {
    final message = YtDlpErrorCleaner.clean(
      '[youtube] abc123: Private video. Sign in if you have access.\n'
      '[youtube] abc123: Requested format is not available. Use --list-formats for a list of available formats',
    );

    expect(message, contains('No downloadable formats were available'));
    expect(message, contains('selected browser cookies'));
  });

  test('explains unavailable formats without auth hints', () {
    final message = YtDlpErrorCleaner.clean(
      '[youtube] abc123: Requested format is not available. Use --list-formats for a list of available formats',
    );

    expect(message, contains('No downloadable formats were available'));
    expect(message, contains('region restricted'));
  });
}
