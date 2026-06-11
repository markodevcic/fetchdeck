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
}

class YtDlpException implements Exception {
  const YtDlpException(this.message);

  final String message;

  @override
  String toString() => message;
}
