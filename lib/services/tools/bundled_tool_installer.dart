import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class BundledToolInstaller {
  const BundledToolInstaller();

  Future<BundledToolPaths> installCurrentPlatformTools() async {
    final platform = _platformName;
    if (platform == null) return const BundledToolPaths();

    final supportDirectory = await getApplicationCacheDirectory();
    final toolDirectory = Directory(
      '${supportDirectory.path}${Platform.pathSeparator}tools'
      '${Platform.pathSeparator}$platform',
    );
    await toolDirectory.create(recursive: true);

    final executableSuffix = Platform.isWindows ? '.exe' : '';
    final ytDlp = await _installTool(
      assetPath: 'assets/tools/current/yt-dlp$executableSuffix',
      destinationPath:
          '${toolDirectory.path}${Platform.pathSeparator}yt-dlp$executableSuffix',
    );
    final ffmpeg = await _installTool(
      assetPath: 'assets/tools/current/ffmpeg$executableSuffix',
      destinationPath:
          '${toolDirectory.path}${Platform.pathSeparator}ffmpeg$executableSuffix',
    );
    final ffprobe = await _installTool(
      assetPath: 'assets/tools/current/ffprobe$executableSuffix',
      destinationPath:
          '${toolDirectory.path}${Platform.pathSeparator}ffprobe$executableSuffix',
    );

    final manifest = await _loadManifest();
    return BundledToolPaths(
      ytDlp: ytDlp,
      ytDlpVersion: manifest['yt-dlp'],
      ffmpeg: ffmpeg,
      ffmpegVersion: manifest['ffmpeg'],
      ffprobe: ffprobe,
      ffprobeVersion: manifest['ffprobe'],
    );
  }

  String? get _platformName {
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return null;
  }

  Future<String?> _installTool({
    required String assetPath,
    required String destinationPath,
  }) async {
    final bytes = await _loadOptionalAsset(assetPath);
    if (bytes == null) return null;

    final destination = File(destinationPath);
    final destinationExists = await destination.exists();
    if (!destinationExists) {
      await destination.parent.create(recursive: true);
      await destination.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    }

    if (!Platform.isWindows) {
      await Process.run('chmod', ['+x', destination.path]);
    }

    return destination.path;
  }

  Future<ByteData?> _loadOptionalAsset(String assetPath) async {
    try {
      return await rootBundle.load(assetPath);
    } on FlutterError {
      return null;
    }
  }

  Future<Map<String, String>> _loadManifest() async {
    try {
      final json = await rootBundle.loadString(
        'assets/tools/current/manifest.json',
      );
      final decoded = jsonDecode(json);
      if (decoded is! Map) return const {};
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
    } on Object {
      return const {};
    }
  }
}

class BundledToolPaths {
  const BundledToolPaths({
    this.ytDlp,
    this.ytDlpVersion,
    this.ffmpeg,
    this.ffmpegVersion,
    this.ffprobe,
    this.ffprobeVersion,
  });

  final String? ytDlp;
  final String? ytDlpVersion;
  final String? ffmpeg;
  final String? ffmpegVersion;
  final String? ffprobe;
  final String? ffprobeVersion;
}
