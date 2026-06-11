import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/download_models.dart';

class YtDlpService {
  const YtDlpService({required this.executable});

  final String executable;

  Future<MediaInfo> getMetadata(String url) async {
    if (url.trim().isEmpty) {
      throw const YtDlpException('URL is empty.');
    }

    final result =
        await Process.run(executable, [
          '-J',
          '--no-warnings',
          '--skip-download',
          url,
        ], runInShell: Platform.isWindows).timeout(
          const Duration(seconds: 45),
          onTimeout: () {
            throw const YtDlpException('yt-dlp metadata request timed out.');
          },
        );

    if (result.exitCode != 0) {
      throw YtDlpException(_cleanError(result.stderr));
    }

    try {
      final payload = jsonDecode(result.stdout as String);
      if (payload is! Map<String, dynamic>) {
        throw const YtDlpException('yt-dlp returned an unexpected JSON shape.');
      }
      return MediaInfoParser.fromJson(payload, fallbackUrl: url);
    } on FormatException catch (error) {
      throw YtDlpException('Could not parse yt-dlp JSON: ${error.message}');
    }
  }

  Future<YtDlpDownloadSession> startDownload({
    required String url,
    required PresetDefinition preset,
    required String outputDirectory,
    required bool isPlaylist,
    String? ffmpegPath,
    String? selectedFormatId,
  }) async {
    if (url.trim().isEmpty) {
      throw const YtDlpException('URL is empty.');
    }

    final arguments = <String>[
      '--newline',
      '--no-warnings',
      '--progress-template',
      'fetchdeck:%(progress.status)s|%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s',
      '-P',
      outputDirectory,
      '-o',
      isPlaylist
          ? '%(playlist_index)03d - %(title).200B [%(id)s].%(ext)s'
          : '%(title).200B [%(id)s].%(ext)s',
      if (ffmpegPath != null) ...[
        '--ffmpeg-location',
        File(ffmpegPath).parent.path,
      ],
      ..._argumentsForPreset(preset, selectedFormatId),
      url,
    ];

    final process = await Process.start(
      executable,
      arguments,
      runInShell: Platform.isWindows,
    );

    final controller = StreamController<DownloadEvent>();
    final stderrLines = <String>[];
    var completed = false;

    void addLine(String line) {
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

  List<String> _argumentsForPreset(
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
    final text = stderr.toString().trim();
    if (text.isEmpty) return 'yt-dlp failed without an error message.';
    return text
        .split('\n')
        .map((line) => line.replaceFirst(RegExp(r'^ERROR:\s*'), ''))
        .join('\n')
        .trim();
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
    );
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
