import 'dart:async';
import 'dart:io';

class ToolDiscovery {
  Future<ToolSet> inspect() async {
    final results = await Future.wait([
      findTool(
        executableNames: Platform.isWindows
            ? const ['yt-dlp.exe', 'yt-dlp']
            : const ['yt-dlp', 'yt-dlp_macos'],
        fallbackPaths: _ytDlpFallbackPaths,
        versionArguments: const ['--version'],
      ),
      findTool(
        executableNames: Platform.isWindows
            ? const ['ffmpeg.exe', 'ffmpeg']
            : const ['ffmpeg'],
        fallbackPaths: _ffmpegFallbackPaths('ffmpeg'),
        versionArguments: const ['-version'],
      ),
      findTool(
        executableNames: Platform.isWindows
            ? const ['ffprobe.exe', 'ffprobe']
            : const ['ffprobe'],
        fallbackPaths: _ffmpegFallbackPaths('ffprobe'),
        versionArguments: const ['-version'],
      ),
    ]);

    return ToolSet(ytDlp: results[0], ffmpeg: results[1], ffprobe: results[2]);
  }

  Future<ToolInfo> findTool({
    required List<String> executableNames,
    required List<String> fallbackPaths,
    required List<String> versionArguments,
  }) async {
    final candidates = <String>{
      ...executableNames,
      for (final directory in _pathDirectories)
        for (final executable in executableNames) '$directory/$executable',
      ...fallbackPaths,
    };

    for (final candidate in candidates) {
      final version = await _readVersion(candidate, versionArguments);
      if (version != null) {
        return ToolInfo.available(path: candidate, version: version);
      }
    }

    return const ToolInfo.missing();
  }

  List<String> get _pathDirectories {
    final rawPath = Platform.environment['PATH'];
    if (rawPath == null || rawPath.isEmpty) return const [];
    return rawPath
        .split(Platform.isWindows ? ';' : ':')
        .where((entry) => entry.trim().isNotEmpty)
        .toList(growable: false);
  }

  List<String> get _ytDlpFallbackPaths {
    final home =
        Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
    return [
      if (Platform.isMacOS) ...const [
        '/opt/homebrew/bin/yt-dlp',
        '/usr/local/bin/yt-dlp',
        '/usr/bin/yt-dlp',
      ],
      if (Platform.isLinux) ...const [
        '/usr/local/bin/yt-dlp',
        '/usr/bin/yt-dlp',
        '/snap/bin/yt-dlp',
      ],
      if (Platform.isWindows) ...const [
        r'C:\Program Files\yt-dlp\yt-dlp.exe',
        r'C:\Program Files (x86)\yt-dlp\yt-dlp.exe',
      ],
      if (home != null && !Platform.isWindows) ...[
        '$home/.local/bin/yt-dlp',
        '$home/Downloads/yt-dlp',
        '$home/Downloads/yt-dlp_macos',
      ],
      if (home != null && Platform.isWindows) ...[
        '$home\\Downloads\\yt-dlp.exe',
        '$home\\AppData\\Local\\Microsoft\\WinGet\\Links\\yt-dlp.exe',
      ],
    ];
  }

  List<String> _ffmpegFallbackPaths(String executable) {
    final suffix = Platform.isWindows ? '$executable.exe' : executable;
    final home =
        Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];

    return [
      if (Platform.isMacOS) ...[
        '/opt/homebrew/bin/$suffix',
        '/usr/local/bin/$suffix',
        '/usr/bin/$suffix',
      ],
      if (Platform.isLinux) ...[
        '/usr/local/bin/$suffix',
        '/usr/bin/$suffix',
        '/snap/bin/$suffix',
      ],
      if (Platform.isWindows) ...[
        'C:\\ffmpeg\\bin\\$suffix',
        'C:\\Program Files\\ffmpeg\\bin\\$suffix',
      ],
      if (home != null && !Platform.isWindows) '$home/.local/bin/$suffix',
    ];
  }

  Future<String?> _readVersion(
    String executable,
    List<String> arguments,
  ) async {
    try {
      final result = await Process.run(
        executable,
        arguments,
        runInShell: Platform.isWindows,
      ).timeout(const Duration(seconds: 4));

      if (result.exitCode != 0) return null;
      final output = '${result.stdout}\n${result.stderr}'.trim();
      if (output.isEmpty) return 'available';
      return output.split('\n').first.trim();
    } on TimeoutException {
      return null;
    } on ProcessException {
      return null;
    } on FileSystemException {
      return null;
    }
  }
}

class ToolSet {
  const ToolSet({
    required this.ytDlp,
    required this.ffmpeg,
    required this.ffprobe,
  });

  const ToolSet.empty()
    : ytDlp = const ToolInfo.missing(),
      ffmpeg = const ToolInfo.missing(),
      ffprobe = const ToolInfo.missing();

  final ToolInfo ytDlp;
  final ToolInfo ffmpeg;
  final ToolInfo ffprobe;
}

class ToolInfo {
  const ToolInfo.available({required this.path, required this.version})
    : isAvailable = true;

  const ToolInfo.missing() : isAvailable = false, path = null, version = null;

  final bool isAvailable;
  final String? path;
  final String? version;

  String shortLabel(String name) {
    if (!isAvailable) return '$name missing';
    final rawVersion = version ?? 'available';
    return '$name $rawVersion';
  }
}
