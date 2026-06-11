enum DownloadStatus {
  ready('Ready'),
  queued('Queued'),
  analyzing('Analyzing'),
  downloading('Downloading'),
  failed('Failed'),
  complete('Complete');

  const DownloadStatus(this.label);

  final String label;
}

enum DownloadPreset {
  mp3_320('MP3 320', '-f ba -x --audio-format mp3 --audio-quality 320K'),
  bestAudio('Best Audio', '-f ba -x'),
  bestMp4(
    'Best MP4 1080p',
    '-f bv*[height<=1080]+ba/b[height<=1080] --merge-output-format mp4',
  ),
  bestVideo('Best Available', '-f bv*+ba/b');

  const DownloadPreset(this.label, this.commandSummary);

  final String label;
  final String commandSummary;
}

class DownloadJob {
  const DownloadJob({
    required this.id,
    required this.url,
    required this.title,
    required this.source,
    required this.preset,
    required this.status,
    required this.progress,
    required this.eta,
    this.mediaInfo,
    this.error,
  });

  final String id;
  final String url;
  final String title;
  final String source;
  final DownloadPreset preset;
  final DownloadStatus status;
  final double progress;
  final String eta;
  final MediaInfo? mediaInfo;
  final String? error;

  DownloadJob copyWith({
    String? title,
    String? source,
    DownloadPreset? preset,
    DownloadStatus? status,
    double? progress,
    String? eta,
    MediaInfo? mediaInfo,
    String? error,
  }) {
    return DownloadJob(
      id: id,
      url: url,
      title: title ?? this.title,
      source: source ?? this.source,
      preset: preset ?? this.preset,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      eta: eta ?? this.eta,
      mediaInfo: mediaInfo ?? this.mediaInfo,
      error: error,
    );
  }
}

class MediaInfo {
  const MediaInfo({
    required this.title,
    required this.webpageUrl,
    required this.extractor,
    required this.formatCount,
    this.uploader,
    this.thumbnail,
    this.duration,
    this.playlistTitle,
    this.playlistCount,
  });

  final String title;
  final String webpageUrl;
  final String extractor;
  final int formatCount;
  final String? uploader;
  final String? thumbnail;
  final Duration? duration;
  final String? playlistTitle;
  final int? playlistCount;

  bool get isPlaylist => playlistCount != null && playlistCount! > 1;

  String get sourceLabel {
    if (extractor.isNotEmpty) return extractor;
    final host = Uri.tryParse(webpageUrl)?.host;
    return host == null || host.isEmpty ? webpageUrl : host;
  }

  String get durationLabel {
    final value = duration;
    if (value == null) return 'Unknown duration';

    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '${value.inMinutes}:$seconds';
  }
}
