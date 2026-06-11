import 'package:shared_preferences/shared_preferences.dart';

import '../../models/download_models.dart';

class AppSettingsRepository {
  const AppSettingsRepository();

  static const _outputDirectoryKey = 'settings.output_directory';
  static const _selectedPresetKey = 'settings.selected_preset';
  static const _ytDlpPathKey = 'settings.yt_dlp_path';
  static const _ffmpegPathKey = 'settings.ffmpeg_path';
  static const _ffprobePathKey = 'settings.ffprobe_path';

  Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      outputDirectory: prefs.getString(_outputDirectoryKey),
      selectedPresetId: _selectedPresetId(prefs.getString(_selectedPresetKey)),
      ytDlpPath: prefs.getString(_ytDlpPathKey),
      ffmpegPath: prefs.getString(_ffmpegPathKey),
      ffprobePath: prefs.getString(_ffprobePathKey),
    );
  }

  Future<void> saveOutputDirectory(String outputDirectory) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_outputDirectoryKey, outputDirectory);
  }

  Future<void> saveSelectedPreset(PresetDefinition preset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedPresetKey, preset.id);
  }

  Future<void> saveToolPaths({
    String? ytDlpPath,
    String? ffmpegPath,
    String? ffprobePath,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _setOrRemove(prefs, _ytDlpPathKey, ytDlpPath);
    await _setOrRemove(prefs, _ffmpegPathKey, ffmpegPath);
    await _setOrRemove(prefs, _ffprobePathKey, ffprobePath);
  }

  Future<void> saveYtDlpPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    await _setOrRemove(prefs, _ytDlpPathKey, path);
  }

  Future<void> saveFfmpegPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    await _setOrRemove(prefs, _ffmpegPathKey, path);
  }

  Future<void> saveFfprobePath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    await _setOrRemove(prefs, _ffprobePathKey, path);
  }

  Future<void> _setOrRemove(
    SharedPreferences prefs,
    String key,
    String? value,
  ) {
    if (value == null || value.trim().isEmpty) {
      return prefs.remove(key);
    }
    return prefs.setString(key, value);
  }

  String? _selectedPresetId(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (value.startsWith('builtin:') || value.startsWith('custom:')) {
      return value;
    }
    final legacyPreset = DownloadPreset.byName(value);
    return legacyPreset?.toDefinition().id ?? value;
  }
}

class AppSettings {
  const AppSettings({
    this.outputDirectory,
    this.selectedPresetId,
    this.ytDlpPath,
    this.ffmpegPath,
    this.ffprobePath,
  });

  final String? outputDirectory;
  final String? selectedPresetId;
  final String? ytDlpPath;
  final String? ffmpegPath;
  final String? ffprobePath;
}
