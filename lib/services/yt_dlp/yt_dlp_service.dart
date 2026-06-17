import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/download_models.dart';
import 'yt_dlp_authentication.dart';
import 'yt_dlp_metadata_service.dart';

class YtDlpService implements YtDlpMetadataService {
  const YtDlpService({required this.executable});

  static const _standardMetadataTimeout = Duration(seconds: 45);
  static const _authenticatedMetadataTimeout = Duration(minutes: 3);

  final String executable;

  @override
  Future<MediaInfo> getMetadata(
    String url, {
    YtDlpAuthentication authentication = YtDlpAuthentication.none,
  }) async {
    if (url.trim().isEmpty) {
      throw const YtDlpException('URL is empty.');
    }

    final result = await _runMetadataProcess([
      '-J',
      '--no-warnings',
      '--skip-download',
      '--ignore-no-formats-error',
      '--no-check-formats',
      ...authentication.arguments,
      url,
    ], authentication: authentication);

    if (result.exitCode != 0) {
      throw YtDlpException(_cleanError(result.stderr));
    }

    try {
      final payload = jsonDecode(result.stdout);
      if (payload is! Map<String, dynamic>) {
        throw const YtDlpException('yt-dlp returned an unexpected JSON shape.');
      }
      return MediaInfoParser.fromJson(payload, fallbackUrl: url);
    } on FormatException catch (error) {
      throw YtDlpException('Could not parse yt-dlp JSON: ${error.message}');
    }
  }

  Future<_YtDlpRunResult> _runMetadataProcess(
    List<String> arguments, {
    required YtDlpAuthentication authentication,
  }) async {
    final process = await Process.start(
      executable,
      arguments,
      runInShell: Platform.isWindows,
    );
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final stdoutDone = Completer<void>();
    final stderrDone = Completer<void>();

    final stdoutSubscription = process.stdout
        .transform(utf8.decoder)
        .listen(stdout.write, onDone: stdoutDone.complete);
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .listen(stderr.write, onDone: stderrDone.complete);

    try {
      final timeout = _metadataTimeoutFor(authentication);
      final exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          process.kill();
          throw TimeoutException(
            _metadataTimeoutMessage(
              authentication,
              timeout: timeout,
              stderr: stderr.toString(),
              stdout: stdout.toString(),
            ),
            timeout,
          );
        },
      );
      await Future.wait([
        stdoutDone.future,
        stderrDone.future,
      ]).timeout(const Duration(seconds: 2), onTimeout: () => const []);
      return _YtDlpRunResult(
        exitCode: exitCode,
        stdout: stdout.toString(),
        stderr: stderr.toString(),
      );
    } on TimeoutException catch (error) {
      throw YtDlpException(
        error.message ??
            _metadataTimeoutMessage(
              authentication,
              timeout: _metadataTimeoutFor(authentication),
              stderr: stderr.toString(),
              stdout: stdout.toString(),
            ),
      );
    } finally {
      await stdoutSubscription.cancel();
      await stderrSubscription.cancel();
    }
  }

  Future<YtDlpDownloadSession> startDownload({
    required String url,
    required PresetDefinition preset,
    required String outputDirectory,
    required bool isPlaylist,
    String? ffmpegPath,
    String? selectedFormatId,
    String? downloadSection,
    String? outputTemplate,
    YtDlpAuthentication authentication = YtDlpAuthentication.none,
  }) async {
    if (url.trim().isEmpty) {
      throw const YtDlpException('URL is empty.');
    }

    final arguments = buildDownloadArguments(
      url: url,
      preset: preset,
      outputDirectory: outputDirectory,
      isPlaylist: isPlaylist,
      ffmpegPath: ffmpegPath,
      selectedFormatId: selectedFormatId,
      downloadSection: downloadSection,
      outputTemplate: outputTemplate,
      authentication: authentication,
    );

    final process = await Process.start(
      executable,
      arguments,
      runInShell: Platform.isWindows,
    );

    final controller = StreamController<DownloadEvent>();
    final stderrLines = <String>[];
    var completed = false;

    void addLine(String line) {
      final outputPath = DownloadOutputParser.parse(line);
      if (outputPath != null && !controller.isClosed) {
        controller.add(DownloadOutputEvent(outputPath));
        return;
      }

      final progress = DownloadProgressParser.parse(line);
      if (progress != null && !controller.isClosed) {
        controller.add(DownloadProgressEvent(progress));
      }
    }

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(addLine);
    process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          stderrLines.add(line);
          addLine(line);
        });

    process.exitCode.then((exitCode) {
      if (controller.isClosed) return;
      completed = true;
      if (exitCode == 0) {
        controller.add(const DownloadCompleteEvent());
      } else {
        controller.add(
          DownloadErrorEvent(
            _cleanError(
              stderrLines.isEmpty
                  ? 'yt-dlp exited with code $exitCode.'
                  : stderrLines.join('\n'),
            ),
          ),
        );
      }
      controller.close();
    });

    return YtDlpDownloadSession(
      process: process,
      events: controller.stream,
      onCancel: () {
        if (!completed) {
          process.kill();
        }
      },
    );
  }

  static List<String> buildDownloadArguments({
    required String url,
    required PresetDefinition preset,
    required String outputDirectory,
    required bool isPlaylist,
    String? ffmpegPath,
    String? selectedFormatId,
    String? downloadSection,
    String? outputTemplate,
    YtDlpAuthentication authentication = YtDlpAuthentication.none,
  }) {
    return [
      '--newline',
      '--no-warnings',
      '--progress-template',
      'fetchdeck:%(progress.status)s|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s',
      '--print',
      'after_move:fetchdeck-file:%(filepath)s',
      if (isPlaylist) ...[
        '--yes-playlist',
        '--no-abort-on-error',
      ] else
        '--no-playlist',
      ...authentication.arguments,
      '-P',
      outputDirectory,
      '-o',
      outputTemplate ??
          (isPlaylist
              ? '%(playlist_index)03d - %(title).200B.%(ext)s'
              : '%(title).200B.%(ext)s'),
      if (downloadSection != null) ...['--download-sections', downloadSection],
      if (ffmpegPath != null) ...[
        '--ffmpeg-location',
        File(ffmpegPath).parent.path,
      ],
      ..._argumentsForPreset(preset, selectedFormatId),
      url,
    ];
  }

  static List<String> _argumentsForPreset(
    PresetDefinition preset,
    String? selectedFormatId,
  ) {
    if (selectedFormatId == null || selectedFormatId.trim().isEmpty) {
      return preset.arguments;
    }

    final result = <String>[];
    var replaced = false;
    for (var index = 0; index < preset.arguments.length; index++) {
      final argument = preset.arguments[index];
      if (argument == '-f' || argument == '--format') {
        result
          ..add(argument)
          ..add(selectedFormatId);
        replaced = true;
        index++;
        continue;
      }
      result.add(argument);
    }

    if (replaced) return result;
    return ['-f', selectedFormatId, ...result];
  }

  String _cleanError(Object stderr) {
    return YtDlpErrorCleaner.clean(stderr);
  }

  Duration _metadataTimeoutFor(YtDlpAuthentication authentication) {
    if (authentication.useBrowserCookies) return _authenticatedMetadataTimeout;
    return _standardMetadataTimeout;
  }

  String _metadataTimeoutMessage(
    YtDlpAuthentication authentication, {
    required Duration timeout,
    String stderr = '',
    String stdout = '',
  }) {
    final prefix =
        'yt-dlp metadata request timed out after ${_formatDuration(timeout)}.';
    final detail = _timeoutOutputDetail(stderr: stderr, stdout: stdout);
    if (!authentication.useBrowserCookies) {
      return '$prefix The site may be slow, blocking requests, or waiting on a network response. Try again, or enable browser cookies if this media requires sign-in. $detail';
    }

    final browser = authentication.browser.label;
    if (authentication.browser == BrowserCookieSource.safari) {
      return '$prefix Fetchdeck was using Safari cookies. If Full Disk Access was just changed, fully quit and reopen Fetchdeck. Safari cookie extraction can also stall when macOS has not applied the permission yet. $detail';
    }

    if (authentication.browser.mayPromptForKeychain) {
      return '$prefix Fetchdeck was using $browser cookies. macOS may be waiting for a Keychain prompt to access "$browser Safe Storage"; choose Allow or Always Allow while Fetchdeck is still open, then retry. $detail';
    }

    return '$prefix Fetchdeck was using $browser cookies. Check for a browser/cookie permission prompt, make sure you are signed in in that browser, then retry. $detail';
  }

  String _formatDuration(Duration duration) {
    if (duration.inMinutes >= 1 && duration.inSeconds % 60 == 0) {
      return '${duration.inMinutes} minutes';
    }
    return '${duration.inSeconds} seconds';
  }

  String _timeoutOutputDetail({
    required String stderr,
    required String stdout,
  }) {
    final output = stderr.trim().isNotEmpty ? stderr : stdout;
    final lines = output
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) {
      return 'No yt-dlp output was received before the timeout.';
    }

    final excerpt = lines.length <= 4
        ? lines.join('\n')
        : lines.sublist(lines.length - 4).join('\n');
    return 'Last yt-dlp output: ${_truncate(excerpt, 700)}';
  }

  String _truncate(String value, int maxLength) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength - 1)}…';
  }
}

class _YtDlpRunResult {
  const _YtDlpRunResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
}

class YtDlpErrorCleaner {
  const YtDlpErrorCleaner._();

  static String clean(Object stderr) {
    final text = stderr.toString().trim();
    if (text.isEmpty) return 'yt-dlp failed without an error message.';
    final cleaned = text
        .split('\n')
        .map((line) => line.replaceFirst(RegExp(r'^ERROR:\s*'), ''))
        .join('\n')
        .trim();
    return _friendlyError(cleaned);
  }

  static String _friendlyError(String message) {
    final lower = message.toLowerCase();
    final safariCookiesBlocked =
        lower.contains('operation not permitted') &&
        lower.contains('com.apple.safari') &&
        lower.contains('cookies.binarycookies');
    if (safariCookiesBlocked) {
      return 'macOS blocked access to Safari cookies. Grant Full Disk Access to Fetchdeck in System Settings, then reopen the app, or switch Browser cookies to Chrome/Firefox/Brave.';
    }

    final requestedFormatUnavailable = lower.contains(
      'requested format is not available',
    );
    final authBlocked =
        lower.contains('private video') ||
        lower.contains('sign in') ||
        lower.contains('login') ||
        lower.contains('cookies');
    if (requestedFormatUnavailable && authBlocked) {
      return 'No downloadable formats were available for one or more playlist entries. YouTube is reporting private/sign-in restricted videos, so Fetchdeck can only download them if the selected browser cookies belong to an account that can access those exact videos. If you can play them in a browser, select that browser in Settings, approve any macOS Keychain or Full Disk Access prompts, then retry.';
    }

    if (requestedFormatUnavailable) {
      return 'No downloadable formats were available for one or more entries. The media may be unavailable, region restricted, DRM protected, or not exposing a stream yt-dlp can download.';
    }

    return message;
  }

  static bool looksAuthenticationRequired(String message) {
    final lower = message.toLowerCase();
    return lower.contains('private video') ||
        lower.contains('sign in') ||
        lower.contains('login') ||
        lower.contains('cookies') ||
        lower.contains('account') ||
        lower.contains('confirm your age');
  }
}

class YtDlpDownloadSession {
  const YtDlpDownloadSession({
    required this.process,
    required this.events,
    required this.onCancel,
  });

  final Process process;
  final Stream<DownloadEvent> events;
  final VoidCallback onCancel;

  void cancel() => onCancel();
}

typedef VoidCallback = void Function();

class DownloadOutputParser {
  static String? parse(String line) {
    const prefix = 'fetchdeck-file:';
    final index = line.indexOf(prefix);
    if (index == -1) return null;

    final path = line.substring(index + prefix.length).trim();
    return path.isEmpty ? null : path;
  }
}

class DownloadProgressParser {
  static DownloadProgress? parse(String line) {
    const prefix = 'fetchdeck:';
    final index = line.indexOf(prefix);
    if (index == -1) return null;

    final payload = line.substring(index + prefix.length);
    final parts = payload.split('|');
    if (parts.isEmpty) return null;

    return DownloadProgress(
      status: parts.elementAtOrNull(0)?.trim() ?? 'downloading',
      percent: _percent(parts.elementAtOrNull(1)),
      speed: _field(parts.elementAtOrNull(2)),
      eta: _field(parts.elementAtOrNull(3)),
    );
  }

  static double? _percent(String? value) {
    if (value == null) return null;
    final normalized = value.replaceAll('%', '').trim();
    return double.tryParse(normalized);
  }

  static String? _field(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == 'N/A') return null;
    return trimmed;
  }
}

class MediaInfoParser {
  static MediaInfo fromJson(
    Map<String, dynamic> json, {
    required String fallbackUrl,
  }) {
    final entries = json['entries'];
    final parsedEntries = _entries(entries, fallbackUrl: fallbackUrl);
    final playlistCount = entries is List ? entries.length : null;
    final firstEntry =
        entries is List && entries.isNotEmpty && entries.first is Map
        ? Map<String, dynamic>.from(entries.first as Map)
        : null;

    final title =
        _string(json['title']) ??
        _string(firstEntry?['title']) ??
        _string(json['fulltitle']) ??
        fallbackUrl;
    final webpageUrl =
        _string(json['webpage_url']) ??
        _string(firstEntry?['webpage_url']) ??
        fallbackUrl;
    final extractor =
        _string(json['extractor_key']) ??
        _string(json['extractor']) ??
        _string(firstEntry?['extractor_key']) ??
        '';
    final formats = json['formats'];
    final parsedFormats = _formats(formats);
    final parsedChapters = _chapters(json['chapters']);

    return MediaInfo(
      title: title,
      webpageUrl: webpageUrl,
      extractor: extractor,
      formatCount: formats is List ? formats.length : 0,
      uploader: _string(json['uploader']) ?? _string(firstEntry?['uploader']),
      thumbnail:
          _string(json['thumbnail']) ?? _string(firstEntry?['thumbnail']),
      duration:
          _duration(json['duration']) ?? _duration(firstEntry?['duration']),
      playlistTitle:
          _string(json['playlist_title']) ??
          (playlistCount != null ? title : null),
      playlistCount: playlistCount,
      formats: parsedFormats,
      entries: parsedEntries,
      chapters: parsedChapters,
    );
  }

  static List<MediaEntry> _entries(
    Object? entries, {
    required String fallbackUrl,
  }) {
    if (entries is! List) return const [];

    final parsedEntries = <MediaEntry>[];
    for (var index = 0; index < entries.length; index += 1) {
      final rawEntry = entries[index];
      if (rawEntry is! Map) continue;

      final entry = Map<String, dynamic>.from(rawEntry);
      final id = _string(entry['id']) ?? 'entry-${index + 1}';
      final webpageUrl =
          _string(entry['webpage_url']) ??
          _string(entry['original_url']) ??
          _string(entry['url']) ??
          fallbackUrl;
      final title =
          _string(entry['title']) ?? _string(entry['fulltitle']) ?? id;
      parsedEntries.add(
        MediaEntry(
          id: id,
          title: title,
          webpageUrl: webpageUrl,
          extractor:
              _string(entry['extractor_key']) ?? _string(entry['extractor']),
          uploader: _string(entry['uploader']),
          thumbnail: _string(entry['thumbnail']),
          duration: _duration(entry['duration']),
          playlistIndex: _int(entry['playlist_index']) ?? index + 1,
        ),
      );
    }

    return parsedEntries;
  }

  static List<MediaChapter> _chapters(Object? chapters) {
    if (chapters is! List) return const [];

    final parsedChapters = <MediaChapter>[];
    for (var index = 0; index < chapters.length; index += 1) {
      final rawChapter = chapters[index];
      if (rawChapter is! Map) continue;

      final chapter = Map<String, dynamic>.from(rawChapter);
      final startTime = _duration(chapter['start_time']);
      final endTime = _duration(chapter['end_time']);
      if (startTime == null || endTime == null || endTime <= startTime) {
        continue;
      }

      parsedChapters.add(
        MediaChapter(
          title: _string(chapter['title']) ?? 'Chapter ${index + 1}',
          startTime: startTime,
          endTime: endTime,
        ),
      );
    }

    return parsedChapters;
  }

  static List<MediaFormat> _formats(Object? formats) {
    if (formats is! List) return const [];

    final parsedFormats = formats
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .map(_format)
        .whereType<MediaFormat>()
        .toList(growable: false);

    return parsedFormats..sort(_compareFormats);
  }

  static int _compareFormats(MediaFormat a, MediaFormat b) {
    final groupCompare = a.group.index.compareTo(b.group.index);
    if (groupCompare != 0) return groupCompare;

    final aHeight = _heightFromResolution(a.resolution);
    final bHeight = _heightFromResolution(b.resolution);
    if (aHeight != bHeight) return bHeight.compareTo(aHeight);

    return a.id.compareTo(b.id);
  }

  static MediaFormat? _format(Map<String, dynamic> json) {
    final id = _string(json['format_id']);
    if (id == null) return null;

    final resolution =
        _string(json['resolution']) ??
        _string(json['format_note']) ??
        _heightLabel(json['height']);
    final extension = _string(json['ext']);
    final note = _string(json['format_note']);
    final label = [
      id,
      ?extension,
      ?resolution,
      if (note != null && note != resolution) note,
    ].join(' • ');

    return MediaFormat(
      id: id,
      label: label,
      extension: extension,
      resolution: resolution,
      videoCodec: _string(json['vcodec']),
      audioCodec: _string(json['acodec']),
      fileSize: _int(json['filesize']) ?? _int(json['filesize_approx']),
      note: note,
    );
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static Duration? _duration(Object? value) {
    if (value is num) return Duration(seconds: value.round());
    if (value is String) {
      final seconds = num.tryParse(value);
      if (seconds != null) return Duration(seconds: seconds.round());
    }
    return null;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String? _heightLabel(Object? value) {
    final height = _int(value);
    if (height == null) return null;
    return '${height}p';
  }

  static int _heightFromResolution(String? resolution) {
    if (resolution == null) return 0;
    final match = RegExp(r'(\d{3,4})p?').firstMatch(resolution);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }
}

class YtDlpException implements Exception {
  const YtDlpException(this.message);

  final String message;

  @override
  String toString() => message;
}
