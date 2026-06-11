import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class YtDlpUpdateService {
  const YtDlpUpdateService({this.client});

  final HttpClient? client;

  Future<YtDlpUpdateInfo> checkForUpdate({
    required String? currentVersion,
  }) async {
    final latest = await fetchLatestVersion();
    return YtDlpUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latest,
      updateAvailable:
          currentVersion == null ||
          _compareVersions(latest, currentVersion) > 0,
    );
  }

  Future<String> fetchLatestVersion() async {
    final response = await _get(
      Uri.parse('https://github.com/yt-dlp/yt-dlp/releases/latest'),
      followRedirects: false,
    );
    final locationHeader = response.headers.value(HttpHeaders.locationHeader);
    await response.drain<void>();

    final location = locationHeader == null
        ? null
        : Uri.tryParse(locationHeader);
    final pathSegments = location?.pathSegments ?? const <String>[];
    final version = pathSegments.isEmpty ? null : pathSegments.last;
    if (version == null || !_looksLikeVersion(version)) {
      throw const YtDlpUpdateException(
        'Could not determine the latest yt-dlp version.',
      );
    }
    return version;
  }

  Future<YtDlpInstallResult> installLatest() async {
    final downloadUrl = _downloadUriForCurrentPlatform();
    final destination = await _activeToolFile();
    final tempFile = File('${destination.path}.download');
    final backupFile = File('${destination.path}.bak');

    await destination.parent.create(recursive: true);
    await _download(downloadUrl, tempFile);
    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', tempFile.path]);
    }

    final installedVersion = await _readVersion(tempFile.path);
    if (installedVersion == null) {
      await _deleteIfExists(tempFile);
      throw const YtDlpUpdateException(
        'Downloaded yt-dlp could not be verified.',
      );
    }

    if (await backupFile.exists()) {
      await backupFile.delete();
    }
    if (await destination.exists()) {
      await destination.rename(backupFile.path);
    }

    try {
      await tempFile.rename(destination.path);
    } catch (_) {
      if (await backupFile.exists() && !await destination.exists()) {
        await backupFile.rename(destination.path);
      }
      rethrow;
    }

    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', destination.path]);
    }

    return YtDlpInstallResult(
      path: destination.path,
      version: installedVersion,
    );
  }

  Future<File> _activeToolFile() async {
    final platform = _platformName;
    if (platform == null) {
      throw const YtDlpUpdateException(
        'yt-dlp updates are supported only on desktop platforms.',
      );
    }
    final supportDirectory = await getApplicationCacheDirectory();
    final suffix = Platform.isWindows ? '.exe' : '';
    return File(
      '${supportDirectory.path}${Platform.pathSeparator}tools'
      '${Platform.pathSeparator}$platform'
      '${Platform.pathSeparator}yt-dlp$suffix',
    );
  }

  Uri _downloadUriForCurrentPlatform() {
    final assetName = switch (_platformName) {
      'macos' => 'yt-dlp_macos',
      'windows' => 'yt-dlp.exe',
      'linux' => 'yt-dlp_linux',
      _ => null,
    };
    if (assetName == null) {
      throw const YtDlpUpdateException(
        'yt-dlp updates are supported only on desktop platforms.',
      );
    }
    return Uri.parse(
      'https://github.com/yt-dlp/yt-dlp/releases/latest/download/$assetName',
    );
  }

  String? get _platformName {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return null;
  }

  Future<HttpClientResponse> _get(
    Uri uri, {
    bool followRedirects = true,
  }) async {
    final httpClient = client ?? HttpClient();
    try {
      final request = await httpClient
          .getUrl(uri)
          .timeout(const Duration(seconds: 15));
      request.followRedirects = followRedirects;
      return await request.close().timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const YtDlpUpdateException('Timed out checking yt-dlp updates.');
    } on SocketException catch (error) {
      throw YtDlpUpdateException('Network error: ${error.message}');
    }
  }

  Future<void> _download(Uri uri, File destination) async {
    final response = await _get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.drain<void>();
      throw YtDlpUpdateException(
        'Download failed with HTTP ${response.statusCode}.',
      );
    }

    final sink = destination.openWrite();
    try {
      await response.pipe(sink);
    } finally {
      await sink.close();
    }
  }

  Future<String?> _readVersion(String executable) async {
    try {
      final result = await Process.run(executable, const [
        '--version',
      ], runInShell: Platform.isWindows).timeout(const Duration(seconds: 8));

      if (result.exitCode != 0) return null;
      final output = '${result.stdout}\n${result.stderr}'.trim();
      return output.isEmpty ? null : output.split('\n').first.trim();
    } on Object {
      return null;
    }
  }

  Future<void> _deleteIfExists(File file) async {
    if (await file.exists()) {
      await file.delete();
    }
  }

  bool _looksLikeVersion(String value) {
    return RegExp(r'^\d{4}\.\d{2}\.\d{2}$').hasMatch(value);
  }

  int _compareVersions(String left, String right) {
    final leftParts = left.split('.').map(int.parse).toList(growable: false);
    final rightParts = right.split('.').map(int.parse).toList(growable: false);
    for (var i = 0; i < leftParts.length; i += 1) {
      final comparison = leftParts[i].compareTo(rightParts[i]);
      if (comparison != 0) return comparison;
    }
    return 0;
  }
}

class YtDlpUpdateInfo {
  const YtDlpUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.updateAvailable,
  });

  final String? currentVersion;
  final String latestVersion;
  final bool updateAvailable;
}

class YtDlpInstallResult {
  const YtDlpInstallResult({required this.path, required this.version});

  final String path;
  final String version;
}

class YtDlpUpdateException implements Exception {
  const YtDlpUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}
