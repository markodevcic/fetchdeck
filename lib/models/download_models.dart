enum DownloadStatus {
  ready('Ready'),
  queued('Queued'),
  analyzing('Analyzing'),
  downloading('Downloading'),
  stopped('Stopped'),
  failed('Failed'),
  complete('Complete');

  const DownloadStatus(this.label);

  final String label;

  static DownloadStatus? byName(String? name) {
    if (name == null) return null;
    for (final status in values) {
      if (status.name == name) return status;
    }
    return null;
  }
}

enum DownloadItemKind {
  playlistEntry('Playlist entry'),
  chapter('Chapter'),
  manualSegment('Manual segment');

  const DownloadItemKind(this.label);

  final String label;

  static DownloadItemKind? byName(String? name) {
    if (name == null) return null;
    for (final kind in values) {
      if (kind.name == name) return kind;
    }
    return null;
  }
}

enum DownloadPreset {
  mp3_320(
    'MP3 320',
    'Transcode best available audio into 320 kbps MP3 with metadata.',
    '-f ba[acodec^=mp3]/ba/b -x --audio-format mp3 --audio-quality 320K',
    [
      '-f',
      'ba[acodec^=mp3]/ba/b',
      '-x',
      '--audio-format',
      'mp3',
      '--audio-quality',
      '320K',
      '--embed-metadata',
      '--embed-thumbnail',
    ],
  ),
  bestAudio(
    'Best Audio',
    'Extract the best available audio stream while keeping its native format.',
    '-f ba -x',
    ['-f', 'ba', '-x'],
  ),
  bestMp4(
    'Best MP4 1080p',
    'Download video up to 1080p and merge to MP4 when needed.',
    '-f bv*[height<=1080]+ba/b[height<=1080] --merge-output-format mp4',
    [
      '-f',
      'bv*[height<=1080]+ba/b[height<=1080]',
      '--merge-output-format',
      'mp4',
    ],
  ),
  bestVideo(
    'Best Available',
    'Download the best available video and audio combination.',
    '-f bv*+ba/b',
    ['-f', 'bv*+ba/b'],
  );

  const DownloadPreset(
    this.label,
    this.description,
    this.commandSummary,
    this.arguments,
  );

  final String label;
  final String description;
  final String commandSummary;
  final List<String> arguments;

  static DownloadPreset? byName(String? name) {
    if (name == null) return null;
    for (final preset in values) {
      if (preset.name == name) return preset;
    }
    return null;
  }

  PresetDefinition toDefinition() {
    return PresetDefinition(
      id: 'builtin:$name',
      label: label,
      description: description,
      commandSummary: commandSummary,
      arguments: arguments,
      isBuiltIn: true,
    );
  }
}

class PresetDefinition {
  const PresetDefinition({
    required this.id,
    required this.label,
    required this.description,
    required this.commandSummary,
    required this.arguments,
    required this.isBuiltIn,
  });

  final String id;
  final String label;
  final String description;
  final String commandSummary;
  final List<String> arguments;
  final bool isBuiltIn;

  bool get looksAudio {
    final haystack = '$id $label ${arguments.join(' ')}'.toLowerCase();
    return haystack.contains('audio') ||
        haystack.contains('mp3') ||
        haystack.contains('m4a') ||
        haystack.contains('opus') ||
        haystack.contains('flac') ||
        haystack.contains('-x');
  }

  static List<PresetDefinition> get builtIns {
    return DownloadPreset.values
        .map((preset) => preset.toDefinition())
        .toList(growable: false);
  }

  static PresetDefinition get defaultPreset =>
      DownloadPreset.mp3_320.toDefinition();

  PresetDefinition copyWith({
    String? id,
    String? label,
    String? description,
    String? commandSummary,
    List<String>? arguments,
    bool? isBuiltIn,
  }) {
    return PresetDefinition(
      id: id ?? this.id,
      label: label ?? this.label,
      description: description ?? this.description,
      commandSummary: commandSummary ?? this.commandSummary,
      arguments: arguments ?? this.arguments,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'label': label,
      'description': description,
      'commandSummary': commandSummary,
      'arguments': arguments,
      'isBuiltIn': isBuiltIn,
    };
  }

  static PresetDefinition? fromJson(Map<String, dynamic> json) {
    final id = _string(json['id']);
    final label = _string(json['label']);
    final arguments = _strings(json['arguments']);
    if (id == null || label == null || arguments.isEmpty) return null;

    return PresetDefinition(
      id: id,
      label: label,
      description: _string(json['description']) ?? 'Custom yt-dlp preset.',
      commandSummary: _string(json['commandSummary']) ?? arguments.join(' '),
      arguments: arguments,
      isBuiltIn: json['isBuiltIn'] == true,
    );
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static List<String> _strings(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  @override
  bool operator ==(Object other) {
    return other is PresetDefinition && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
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
    this.outputPath,
    this.downloadedFilePath,
    this.splitSourceFilePath,
    this.downloadedFileSize,
    this.selectedFormatId,
    this.startedAt,
    this.completedAt,
    this.logLines = const [],
    this.children = const [],
    this.isExpanded = false,
    this.splitPlan,
  });

  final String id;
  final String url;
  final String title;
  final String source;
  final PresetDefinition preset;
  final DownloadStatus status;
  final double progress;
  final String eta;
  final MediaInfo? mediaInfo;
  final String? error;
  final String? outputPath;
  final String? downloadedFilePath;
  final String? splitSourceFilePath;
  final int? downloadedFileSize;
  final String? selectedFormatId;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final List<String> logLines;
  final List<DownloadItem> children;
  final bool isExpanded;
  final SplitPlan? splitPlan;

  String? get splitEditorSourcePath =>
      splitSourceFilePath ?? downloadedFilePath;
  String? get bestOutputPath => downloadedFilePath ?? outputPath;
  bool get hasChildren => children.isNotEmpty;
  int get childCount => children.length;
  int get selectedChildCount =>
      children.where((child) => child.isSelected).length;

  DownloadJob copyWith({
    String? title,
    String? source,
    PresetDefinition? preset,
    DownloadStatus? status,
    double? progress,
    String? eta,
    MediaInfo? mediaInfo,
    String? error,
    String? outputPath,
    String? downloadedFilePath,
    String? splitSourceFilePath,
    int? downloadedFileSize,
    String? selectedFormatId,
    DateTime? startedAt,
    DateTime? completedAt,
    List<String>? logLines,
    List<DownloadItem>? children,
    bool? isExpanded,
    SplitPlan? splitPlan,
    bool clearSelectedFormat = false,
    bool clearOutputPath = false,
    bool clearDownloadedFilePath = false,
    bool clearSplitSourceFilePath = false,
    bool clearDownloadedFileSize = false,
    bool clearStartedAt = false,
    bool clearCompletedAt = false,
    bool clearSplitPlan = false,
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
      outputPath: clearOutputPath ? null : outputPath ?? this.outputPath,
      downloadedFilePath: clearDownloadedFilePath
          ? null
          : downloadedFilePath ?? this.downloadedFilePath,
      splitSourceFilePath: clearSplitSourceFilePath
          ? null
          : splitSourceFilePath ?? this.splitSourceFilePath,
      downloadedFileSize: clearDownloadedFileSize
          ? null
          : downloadedFileSize ?? this.downloadedFileSize,
      selectedFormatId: clearSelectedFormat
          ? null
          : selectedFormatId ?? this.selectedFormatId,
      startedAt: clearStartedAt ? null : startedAt ?? this.startedAt,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
      logLines: logLines ?? this.logLines,
      children: children ?? this.children,
      isExpanded: isExpanded ?? this.isExpanded,
      splitPlan: clearSplitPlan ? null : splitPlan ?? this.splitPlan,
    );
  }

  DownloadJob appendLog(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return this;

    final nextLines = [...logLines, trimmed];
    const maxLines = 80;
    return copyWith(
      logLines: nextLines.length <= maxLines
          ? nextLines
          : nextLines.sublist(nextLines.length - maxLines),
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'url': url,
      'title': title,
      'source': source,
      'presetId': preset.id,
      'presetLabel': preset.label,
      'presetDescription': preset.description,
      'presetCommandSummary': preset.commandSummary,
      'presetArguments': preset.arguments,
      'presetIsBuiltIn': preset.isBuiltIn,
      'status': status.name,
      'progress': progress,
      'eta': eta,
      'mediaInfo': mediaInfo?.toJson(),
      'error': error,
      'outputPath': outputPath,
      'downloadedFilePath': downloadedFilePath,
      'splitSourceFilePath': splitSourceFilePath,
      'downloadedFileSize': downloadedFileSize,
      'selectedFormatId': selectedFormatId,
      'startedAt': startedAt?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'logLines': logLines,
      'children': children.map((child) => child.toJson()).toList(),
      'isExpanded': isExpanded,
      'splitPlan': splitPlan?.toJson(),
    };
  }

  static DownloadJob? fromJson(Map<String, dynamic> json) {
    final id = _string(json['id']);
    final url = _string(json['url']);
    final title = _string(json['title']);
    final source = _string(json['source']);
    final preset = _presetFromJson(json);
    final status = DownloadStatus.byName(_string(json['status']));
    if (id == null ||
        url == null ||
        title == null ||
        source == null ||
        preset == null ||
        status == null) {
      return null;
    }

    final mediaJson = json['mediaInfo'];
    return DownloadJob(
      id: id,
      url: url,
      title: title,
      source: source,
      preset: preset,
      status: status,
      progress: _double(json['progress']) ?? 0,
      eta: _string(json['eta']) ?? status.label,
      mediaInfo: mediaJson is Map<String, dynamic>
          ? MediaInfo.fromJson(mediaJson)
          : null,
      error: _string(json['error']),
      outputPath: _string(json['outputPath']),
      downloadedFilePath: _string(json['downloadedFilePath']),
      splitSourceFilePath: _string(json['splitSourceFilePath']),
      downloadedFileSize: _int(json['downloadedFileSize']),
      selectedFormatId: _string(json['selectedFormatId']),
      startedAt: _dateTime(json['startedAt']),
      completedAt: _dateTime(json['completedAt']),
      logLines: _strings(json['logLines']),
      children: _children(json['children']),
      isExpanded: json['isExpanded'] == true,
      splitPlan: _splitPlan(json['splitPlan']),
    );
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _dateTime(Object? value) {
    final text = _string(value);
    if (text == null) return null;
    return DateTime.tryParse(text);
  }

  static List<String> _strings(Object? value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  static List<DownloadItem> _children(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => DownloadItem.fromJson(Map<String, dynamic>.from(item)))
        .whereType<DownloadItem>()
        .toList(growable: false);
  }

  static SplitPlan? _splitPlan(Object? value) {
    if (value is! Map) return null;
    return SplitPlan.fromJson(Map<String, dynamic>.from(value));
  }

  static PresetDefinition? _presetFromJson(Map<String, dynamic> json) {
    final presetJson = {
      'id': _string(json['presetId']),
      'label': _string(json['presetLabel']),
      'description': _string(json['presetDescription']),
      'commandSummary': _string(json['presetCommandSummary']),
      'arguments': json['presetArguments'],
      'isBuiltIn': json['presetIsBuiltIn'],
    };
    final restored = PresetDefinition.fromJson(presetJson);
    if (restored != null) return restored;

    final legacyPreset = DownloadPreset.byName(_string(json['preset']));
    return legacyPreset?.toDefinition();
  }
}

class DownloadItem {
  const DownloadItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.status,
    required this.progress,
    this.url,
    this.source,
    this.thumbnail,
    this.duration,
    this.startTime,
    this.endTime,
    this.sourceFilePath,
    this.fadeDuration,
    this.error,
    this.outputPath,
    this.downloadedFilePath,
    this.downloadedFileSize,
    this.startedAt,
    this.completedAt,
    this.isSelected = true,
  });

  final String id;
  final DownloadItemKind kind;
  final String title;
  final String? url;
  final String? source;
  final String? thumbnail;
  final Duration? duration;
  final Duration? startTime;
  final Duration? endTime;
  final String? sourceFilePath;
  final Duration? fadeDuration;
  final DownloadStatus status;
  final double progress;
  final String? error;
  final String? outputPath;
  final String? downloadedFilePath;
  final int? downloadedFileSize;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final bool isSelected;

  String? get bestOutputPath => downloadedFilePath ?? outputPath;

  DownloadItem copyWith({
    String? title,
    String? url,
    String? source,
    String? thumbnail,
    Duration? duration,
    Duration? startTime,
    Duration? endTime,
    String? sourceFilePath,
    Duration? fadeDuration,
    DownloadStatus? status,
    double? progress,
    String? error,
    String? outputPath,
    String? downloadedFilePath,
    int? downloadedFileSize,
    DateTime? startedAt,
    DateTime? completedAt,
    bool? isSelected,
    bool clearError = false,
    bool clearOutputPath = false,
    bool clearDownloadedFilePath = false,
    bool clearDownloadedFileSize = false,
    bool clearStartedAt = false,
    bool clearCompletedAt = false,
    bool clearSourceFilePath = false,
    bool clearFadeDuration = false,
  }) {
    return DownloadItem(
      id: id,
      kind: kind,
      title: title ?? this.title,
      url: url ?? this.url,
      source: source ?? this.source,
      thumbnail: thumbnail ?? this.thumbnail,
      duration: duration ?? this.duration,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      sourceFilePath: clearSourceFilePath
          ? null
          : sourceFilePath ?? this.sourceFilePath,
      fadeDuration: clearFadeDuration
          ? null
          : fadeDuration ?? this.fadeDuration,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: clearError ? null : error ?? this.error,
      outputPath: clearOutputPath ? null : outputPath ?? this.outputPath,
      downloadedFilePath: clearDownloadedFilePath
          ? null
          : downloadedFilePath ?? this.downloadedFilePath,
      downloadedFileSize: clearDownloadedFileSize
          ? null
          : downloadedFileSize ?? this.downloadedFileSize,
      startedAt: clearStartedAt ? null : startedAt ?? this.startedAt,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'kind': kind.name,
      'title': title,
      'url': url,
      'source': source,
      'thumbnail': thumbnail,
      'durationSeconds': duration?.inSeconds,
      'startSeconds': startTime?.inSeconds,
      'endSeconds': endTime?.inSeconds,
      'sourceFilePath': sourceFilePath,
      'fadeMilliseconds': fadeDuration?.inMilliseconds,
      'status': status.name,
      'progress': progress,
      'error': error,
      'outputPath': outputPath,
      'downloadedFilePath': downloadedFilePath,
      'downloadedFileSize': downloadedFileSize,
      'startedAt': startedAt?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'isSelected': isSelected,
    };
  }

  static DownloadItem? fromJson(Map<String, dynamic> json) {
    final id = _string(json['id']);
    final kind = DownloadItemKind.byName(_string(json['kind']));
    final title = _string(json['title']);
    final status = DownloadStatus.byName(_string(json['status']));
    if (id == null || kind == null || title == null || status == null) {
      return null;
    }

    return DownloadItem(
      id: id,
      kind: kind,
      title: title,
      url: _string(json['url']),
      source: _string(json['source']),
      thumbnail: _string(json['thumbnail']),
      duration: _durationFromSeconds(json['durationSeconds']),
      startTime: _durationFromSeconds(json['startSeconds']),
      endTime: _durationFromSeconds(json['endSeconds']),
      sourceFilePath: _string(json['sourceFilePath']),
      fadeDuration: _durationFromMilliseconds(json['fadeMilliseconds']),
      status: status,
      progress: _double(json['progress']) ?? 0,
      error: _string(json['error']),
      outputPath: _string(json['outputPath']),
      downloadedFilePath: _string(json['downloadedFilePath']),
      downloadedFileSize: _int(json['downloadedFileSize']),
      startedAt: _dateTime(json['startedAt']),
      completedAt: _dateTime(json['completedAt']),
      isSelected: json['isSelected'] != false,
    );
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _dateTime(Object? value) {
    final text = _string(value);
    if (text == null) return null;
    return DateTime.tryParse(text);
  }

  static Duration? _durationFromSeconds(Object? value) {
    final seconds = _int(value);
    if (seconds == null) return null;
    return Duration(seconds: seconds);
  }

  static Duration? _durationFromMilliseconds(Object? value) {
    final milliseconds = _int(value);
    if (milliseconds == null) return null;
    return Duration(milliseconds: milliseconds);
  }
}

class SplitMarker {
  const SplitMarker({
    required this.id,
    required this.position,
    required this.title,
  });

  final String id;
  final Duration position;
  final String title;

  SplitMarker copyWith({Duration? position, String? title}) {
    return SplitMarker(
      id: id,
      position: position ?? this.position,
      title: title ?? this.title,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'positionMilliseconds': position.inMilliseconds,
      'title': title,
    };
  }

  static SplitMarker? fromJson(Map<String, dynamic> json) {
    final id = _string(json['id']);
    final title = _string(json['title']);
    final position = _durationFromMilliseconds(json['positionMilliseconds']);
    if (id == null || title == null || position == null) return null;

    return SplitMarker(id: id, position: position, title: title);
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static Duration? _durationFromMilliseconds(Object? value) {
    final milliseconds = _int(value);
    if (milliseconds == null) return null;
    return Duration(milliseconds: milliseconds);
  }
}

class SplitPlan {
  const SplitPlan({
    required this.sourceFilePath,
    required this.markers,
    required this.fadeDuration,
    required this.appliedAt,
  });

  final String sourceFilePath;
  final List<SplitMarker> markers;
  final Duration fadeDuration;
  final DateTime appliedAt;

  bool get hasFade => fadeDuration > Duration.zero;

  SplitPlan copyWith({
    String? sourceFilePath,
    List<SplitMarker>? markers,
    Duration? fadeDuration,
    DateTime? appliedAt,
  }) {
    return SplitPlan(
      sourceFilePath: sourceFilePath ?? this.sourceFilePath,
      markers: markers ?? this.markers,
      fadeDuration: fadeDuration ?? this.fadeDuration,
      appliedAt: appliedAt ?? this.appliedAt,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'sourceFilePath': sourceFilePath,
      'markers': markers.map((marker) => marker.toJson()).toList(),
      'fadeMilliseconds': fadeDuration.inMilliseconds,
      'appliedAt': appliedAt.toIso8601String(),
    };
  }

  static SplitPlan? fromJson(Map<String, dynamic> json) {
    final sourceFilePath = _string(json['sourceFilePath']);
    final appliedAt = _dateTime(json['appliedAt']);
    if (sourceFilePath == null || appliedAt == null) return null;

    return SplitPlan(
      sourceFilePath: sourceFilePath,
      markers: _markers(json['markers']),
      fadeDuration:
          _durationFromMilliseconds(json['fadeMilliseconds']) ?? Duration.zero,
      appliedAt: appliedAt,
    );
  }

  static List<SplitMarker> _markers(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => SplitMarker.fromJson(Map<String, dynamic>.from(item)))
        .whereType<SplitMarker>()
        .toList(growable: false);
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static DateTime? _dateTime(Object? value) {
    final text = _string(value);
    if (text == null) return null;
    return DateTime.tryParse(text);
  }

  static Duration? _durationFromMilliseconds(Object? value) {
    final milliseconds = _int(value);
    if (milliseconds == null) return null;
    return Duration(milliseconds: milliseconds);
  }
}

class DownloadProgress {
  const DownloadProgress({
    required this.status,
    this.percent,
    this.speed,
    this.eta,
  });

  final String status;
  final double? percent;
  final String? speed;
  final String? eta;

  String get label {
    final parts = <String>[
      if (percent != null) '${percent!.toStringAsFixed(1)}%',
      if (speed != null && speed!.isNotEmpty) speed!,
      if (eta != null && eta!.isNotEmpty && eta != 'Unknown') 'ETA $eta',
    ];
    return parts.isEmpty ? status : parts.join(' • ');
  }
}

sealed class DownloadEvent {
  const DownloadEvent();
}

class DownloadProgressEvent extends DownloadEvent {
  const DownloadProgressEvent(this.progress);

  final DownloadProgress progress;
}

class DownloadCompleteEvent extends DownloadEvent {
  const DownloadCompleteEvent();
}

class DownloadOutputEvent extends DownloadEvent {
  const DownloadOutputEvent(this.path);

  final String path;
}

class DownloadErrorEvent extends DownloadEvent {
  const DownloadErrorEvent(this.message);

  final String message;
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
    this.formats = const [],
    this.entries = const [],
    this.chapters = const [],
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
  final List<MediaFormat> formats;
  final List<MediaEntry> entries;
  final List<MediaChapter> chapters;

  bool get isPlaylist => playlistCount != null && playlistCount! > 1;
  bool get hasChapters => chapters.isNotEmpty;

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

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'webpageUrl': webpageUrl,
      'extractor': extractor,
      'formatCount': formatCount,
      'uploader': uploader,
      'thumbnail': thumbnail,
      'durationSeconds': duration?.inSeconds,
      'playlistTitle': playlistTitle,
      'playlistCount': playlistCount,
      'formats': formats.map((format) => format.toJson()).toList(),
      'entries': entries.map((entry) => entry.toJson()).toList(),
      'chapters': chapters.map((chapter) => chapter.toJson()).toList(),
    };
  }

  static MediaInfo? fromJson(Map<String, dynamic> json) {
    final title = _string(json['title']);
    final webpageUrl = _string(json['webpageUrl']);
    final extractor = _string(json['extractor']);
    final formatCount = _int(json['formatCount']);
    if (title == null ||
        webpageUrl == null ||
        extractor == null ||
        formatCount == null) {
      return null;
    }

    final durationSeconds = _int(json['durationSeconds']);
    return MediaInfo(
      title: title,
      webpageUrl: webpageUrl,
      extractor: extractor,
      formatCount: formatCount,
      uploader: _string(json['uploader']),
      thumbnail: _string(json['thumbnail']),
      duration: durationSeconds == null
          ? null
          : Duration(seconds: durationSeconds),
      playlistTitle: _string(json['playlistTitle']),
      playlistCount: _int(json['playlistCount']),
      formats: _formats(json['formats']),
      entries: _entries(json['entries']),
      chapters: _chapters(json['chapters']),
    );
  }

  static List<MediaFormat> _formats(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => MediaFormat.fromJson(Map<String, dynamic>.from(item)))
        .whereType<MediaFormat>()
        .toList(growable: false);
  }

  static List<MediaEntry> _entries(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => MediaEntry.fromJson(Map<String, dynamic>.from(item)))
        .whereType<MediaEntry>()
        .toList(growable: false);
  }

  static List<MediaChapter> _chapters(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => MediaChapter.fromJson(Map<String, dynamic>.from(item)))
        .whereType<MediaChapter>()
        .toList(growable: false);
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class MediaEntry {
  const MediaEntry({
    required this.id,
    required this.title,
    required this.webpageUrl,
    this.extractor,
    this.uploader,
    this.thumbnail,
    this.duration,
    this.playlistIndex,
  });

  final String id;
  final String title;
  final String webpageUrl;
  final String? extractor;
  final String? uploader;
  final String? thumbnail;
  final Duration? duration;
  final int? playlistIndex;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'title': title,
      'webpageUrl': webpageUrl,
      'extractor': extractor,
      'uploader': uploader,
      'thumbnail': thumbnail,
      'durationSeconds': duration?.inSeconds,
      'playlistIndex': playlistIndex,
    };
  }

  static MediaEntry? fromJson(Map<String, dynamic> json) {
    final id = _string(json['id']);
    final title = _string(json['title']);
    final webpageUrl = _string(json['webpageUrl']);
    if (id == null || title == null || webpageUrl == null) return null;

    final durationSeconds = _int(json['durationSeconds']);
    return MediaEntry(
      id: id,
      title: title,
      webpageUrl: webpageUrl,
      extractor: _string(json['extractor']),
      uploader: _string(json['uploader']),
      thumbnail: _string(json['thumbnail']),
      duration: durationSeconds == null
          ? null
          : Duration(seconds: durationSeconds),
      playlistIndex: _int(json['playlistIndex']),
    );
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class MediaChapter {
  const MediaChapter({
    required this.title,
    required this.startTime,
    required this.endTime,
  });

  final String title;
  final Duration startTime;
  final Duration endTime;

  Duration get duration => endTime - startTime;

  Map<String, Object?> toJson() {
    return {
      'title': title,
      'startSeconds': startTime.inSeconds,
      'endSeconds': endTime.inSeconds,
    };
  }

  static MediaChapter? fromJson(Map<String, dynamic> json) {
    final title = _string(json['title']);
    final startTime = _durationFromSeconds(json['startSeconds']);
    final endTime = _durationFromSeconds(json['endSeconds']);
    if (title == null || startTime == null || endTime == null) return null;
    if (endTime <= startTime) return null;

    return MediaChapter(title: title, startTime: startTime, endTime: endTime);
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static Duration? _durationFromSeconds(Object? value) {
    final seconds = _int(value);
    if (seconds == null) return null;
    return Duration(seconds: seconds);
  }
}

class MediaFormat {
  const MediaFormat({
    required this.id,
    required this.label,
    this.extension,
    this.resolution,
    this.videoCodec,
    this.audioCodec,
    this.fileSize,
    this.note,
  });

  final String id;
  final String label;
  final String? extension;
  final String? resolution;
  final String? videoCodec;
  final String? audioCodec;
  final int? fileSize;
  final String? note;

  bool get hasVideo => videoCodec != null && videoCodec != 'none';
  bool get hasAudio => audioCodec != null && audioCodec != 'none';
  bool get isCombined => hasVideo && hasAudio;
  bool get isVideoOnly => hasVideo && !hasAudio;
  bool get isAudioOnly => hasAudio && !hasVideo;

  FormatGroup get group {
    if (isCombined) return FormatGroup.combined;
    if (isVideoOnly) return FormatGroup.video;
    if (isAudioOnly) return FormatGroup.audio;
    return FormatGroup.other;
  }

  String get displayLabel {
    final parts = <String>[
      id,
      group.label,
      ?extension,
      ?resolution,
      if (hasVideo && videoCodec != null) 'v:$videoCodec',
      if (hasAudio && audioCodec != null) 'a:$audioCodec',
      if (fileSize != null) _fileSizeLabel(fileSize!),
      ?note,
    ];
    return parts.join(' • ');
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'label': label,
      'extension': extension,
      'resolution': resolution,
      'videoCodec': videoCodec,
      'audioCodec': audioCodec,
      'fileSize': fileSize,
      'note': note,
    };
  }

  static MediaFormat? fromJson(Map<String, dynamic> json) {
    final id = _string(json['id']);
    if (id == null) return null;
    return MediaFormat(
      id: id,
      label: _string(json['label']) ?? id,
      extension: _string(json['extension']),
      resolution: _string(json['resolution']),
      videoCodec: _string(json['videoCodec']),
      audioCodec: _string(json['audioCodec']),
      fileSize: _int(json['fileSize']),
      note: _string(json['note']),
    );
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static String _fileSizeLabel(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value = value / 1024;
      unitIndex++;
    }
    return '${value.toStringAsFixed(unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
  }
}

enum FormatGroup {
  combined('Combined'),
  video('Video only'),
  audio('Audio only'),
  other('Other');

  const FormatGroup(this.label);

  final String label;
}
