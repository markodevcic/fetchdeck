import 'dart:async';
import 'dart:io';

class ToolDiscovery {
  Future<ToolSet> inspect({
    ToolPathPreferences preferences = const ToolPathPreferences(),
  }) async {
    final results = await Future.wait([
      findTool(
        executableNames: Platform.isWindows
            ? const ['yt-dlp.exe', 'yt-dlp']
            : const ['yt-dlp', 'yt-dlp_macos'],
        preferredPath: preferences.ytDlpPath,
        bundledPath: preferences.bundledYtDlpPath,
        bundledVersion: preferences.bundledYtDlpVersion,
        fallbackPaths: _ytDlpFallbackPaths,
        versionArguments: const ['--version'],
      ),
      findTool(
        executableNames: Platform.isWindows
            ? const ['ffmpeg.exe', 'ffmpeg']
            : const ['ffmpeg'],
        preferredPath: preferences.ffmpegPath,
        bundledPath: preferences.bundledFfmpegPath,
        bundledVersion: preferences.bundledFfmpegVersion,
        fallbackPaths: _ffmpegFallbackPaths('ffmpeg'),
        versionArguments: const ['-version'],
      ),
      findTool(
        executableNames: Platform.isWindows
            ? const ['ffprobe.exe', 'ffprobe']
            : const ['ffprobe'],
        preferredPath: preferences.ffprobePath,
        bundledPath: preferences.bundledFfprobePath,
        bundledVersion: preferences.bundledFfprobeVersion,
        fallbackPaths: _ffmpegFallbackPaths('ffprobe'),
        versionArguments: const ['-version'],
      ),
    ]);

    return ToolSet(ytDlp: results[0], ffmpeg: results[1], ffprobe: results[2]);
  }

  Future<ToolInfo> findTool({
    required List<String> executableNames,
    String? preferredPath,
    String? bundledPath,
    String? bundledVersion,
    required List<String> fallbackPaths,
    required List<String> versionArguments,
  }) async {
    final candidates = _dedupeCandidates([
      if (preferredPath != null && preferredPath.trim().isNotEmpty)
        ToolCandidate(preferredPath, ToolSource.custom),
      if (bundledPath != null && bundledPath.trim().isNotEmpty)
        ToolCandidate(bundledPath, ToolSource.bundled),
      for (final executable in executableNames)
        ToolCandidate(executable, ToolSource.system),
      for (final directory in _pathDirectories)
        for (final executable in executableNames)
          ToolCandidate('$directory/$executable', ToolSource.system),
      for (final path in fallbackPaths) ToolCandidate(path, ToolSource.system),
    ]);
    ToolCandidate? existingCandidate;
    String? existingCandidateError;

    for (final candidate in candidates) {
      final candidateExists = await File(candidate.path).exists();
      if (existingCandidate == null && candidateExists) {
        existingCandidate = candidate;
      }
      if (candidateExists &&
          candidate.source == ToolSource.bundled &&
          bundledVersion != null) {
        return ToolInfo.available(
          path: candidate.path,
          version: bundledVersion,
          source: candidate.source,
        );
      }
      final versionResult = await _readVersion(
        candidate.path,
        versionArguments,
      );
      if (versionResult.version != null) {
        return ToolInfo.available(
          path: candidate.path,
          version: versionResult.version!,
          source: candidate.source,
        );
      }
      if (candidateExists && existingCandidate?.path == candidate.path) {
        existingCandidateError = versionResult.error;
      }
    }

    if (existingCandidate != null) {
      return ToolInfo.missing(
        path: existingCandidate.path,
        source: existingCandidate.source,
        error:
            existingCandidateError ??
            'Found this executable, but it could not be run.',
      );
    }

    return const ToolInfo.missing();
  }

  List<ToolCandidate> _dedupeCandidates(List<ToolCandidate> candidates) {
    final seen = <String>{};
    return [
      for (final candidate in candidates)
        if (seen.add(candidate.path)) candidate,
    ];
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

  Future<ToolVersionResult> _readVersion(
    String executable,
    List<String> arguments,
  ) async {
    try {
      final result = await Process.run(
        executable,
        arguments,
        runInShell: Platform.isWindows,
      ).timeout(const Duration(seconds: 12));

      if (result.exitCode != 0) {
        final output = '${result.stdout}\n${result.stderr}'.trim();
        return ToolVersionResult(
          error: output.isEmpty
              ? 'Exited with code ${result.exitCode}.'
              : output.split('\n').first.trim(),
        );
      }
      final output = '${result.stdout}\n${result.stderr}'.trim();
      if (output.isEmpty) return const ToolVersionResult(version: 'available');
      return ToolVersionResult(version: output.split('\n').first.trim());
    } on TimeoutException {
      return const ToolVersionResult(
        error: 'Timed out while checking version.',
      );
    } on ProcessException catch (error) {
      return ToolVersionResult(error: error.message);
    } on FileSystemException catch (error) {
      return ToolVersionResult(error: error.message);
    }
  }
}

class ToolVersionResult {
  const ToolVersionResult({this.version, this.error});

  final String? version;
  final String? error;
}

class ToolPathPreferences {
  const ToolPathPreferences({
    this.ytDlpPath,
    this.ffmpegPath,
    this.ffprobePath,
    this.bundledYtDlpPath,
    this.bundledYtDlpVersion,
    this.bundledFfmpegPath,
    this.bundledFfmpegVersion,
    this.bundledFfprobePath,
    this.bundledFfprobeVersion,
  });

  final String? ytDlpPath;
  final String? ffmpegPath;
  final String? ffprobePath;
  final String? bundledYtDlpPath;
  final String? bundledYtDlpVersion;
  final String? bundledFfmpegPath;
  final String? bundledFfmpegVersion;
  final String? bundledFfprobePath;
  final String? bundledFfprobeVersion;
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
  const ToolInfo.available({
    required this.path,
    required this.version,
    this.source = ToolSource.system,
  }) : isAvailable = true,
       error = null;

  const ToolInfo.missing({this.path, this.error, this.source})
    : isAvailable = false,
      version = null;

  final bool isAvailable;
  final String? path;
  final String? version;
  final String? error;
  final ToolSource? source;

  String shortLabel(String name) {
    if (!isAvailable && path != null) return '$name blocked';
    if (!isAvailable) return '$name missing';
    final rawVersion = version ?? 'available';
    return '$name ${source?.label ?? 'system'} $rawVersion';
  }
}

class ToolCandidate {
  const ToolCandidate(this.path, this.source);

  final String path;
  final ToolSource source;
}

enum ToolSource {
  custom('Custom'),
  bundled('Bundled'),
  system('System');

  const ToolSource(this.label);

  final String label;
}
