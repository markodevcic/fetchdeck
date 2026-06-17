import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/features/settings/application/app_settings_controller.dart';
import 'package:yt_dlp_desktop/features/settings/application/download_concurrency_limit.dart';
import 'package:yt_dlp_desktop/features/settings/application/tool_controller.dart';
import 'package:yt_dlp_desktop/features/settings/application/tool_kind.dart';
import 'package:yt_dlp_desktop/models/download_models.dart';
import 'package:yt_dlp_desktop/services/settings/app_settings_repository.dart';
import 'package:yt_dlp_desktop/services/tools/bundled_tool_installer.dart';
import 'package:yt_dlp_desktop/services/tools/tool_discovery.dart';
import 'package:yt_dlp_desktop/services/tools/yt_dlp_update_service.dart';

void main() {
  test('inspect installs bundled paths and reports available yt-dlp', () async {
    final discovery = _FakeToolDiscovery();
    final container = _container(discovery: discovery);
    addTearDown(container.dispose);

    final statuses = <String>[];
    final toolSet = await container
        .read(toolControllerProvider.notifier)
        .inspect(settings: const AppSettings(), reportStatus: statuses.add);

    expect(toolSet.ytDlp.path, '/bundled/yt-dlp');
    expect(toolSet.ytDlp.version, '2026.06.01');
    expect(
      container.read(toolControllerProvider).toolSet.ytDlp.isAvailable,
      isTrue,
    );
    expect(discovery.lastPreferences?.bundledYtDlpPath, '/bundled/yt-dlp');
    expect(statuses, contains('Ready. yt-dlp found at /bundled/yt-dlp.'));
  });

  test('setToolPath saves custom path and reinspects tools', () async {
    final repository = _MemorySettingsRepository();
    final discovery = _FakeToolDiscovery();
    final container = _container(
      discovery: discovery,
      settingsRepository: repository,
    );
    addTearDown(container.dispose);

    final statuses = <String>[];
    await container
        .read(toolControllerProvider.notifier)
        .setToolPath(
          tool: ToolKind.ytDlp,
          path: '/custom/yt-dlp',
          reportStatus: statuses.add,
        );

    final state = container.read(toolControllerProvider);
    expect(repository.ytDlpPath, '/custom/yt-dlp');
    expect(state.ytDlpPath, '/custom/yt-dlp');
    expect(state.toolSet.ytDlp.path, '/custom/yt-dlp');
    expect(state.toolSet.ytDlp.source, ToolSource.custom);
    expect(discovery.lastPreferences?.ytDlpPath, '/custom/yt-dlp');
    expect(statuses.last, 'Ready. yt-dlp found at /custom/yt-dlp.');
  });

  test('checkYtDlpUpdate stores update state', () async {
    final container = _container(
      discovery: _FakeToolDiscovery(),
      updateService: const _FakeYtDlpUpdateService(),
    );
    addTearDown(container.dispose);

    final statuses = <String>[];
    await container
        .read(toolControllerProvider.notifier)
        .inspect(settings: const AppSettings(), reportStatus: statuses.add);
    await container
        .read(toolControllerProvider.notifier)
        .checkYtDlpUpdate(reportStatus: statuses.add);

    final state = container.read(toolControllerProvider);
    expect(state.updateInfo?.latestVersion, '2026.06.02');
    expect(state.updateInfo?.updateAvailable, isTrue);
    expect(state.isCheckingYtDlpUpdate, isFalse);
    expect(statuses.last, 'yt-dlp 2026.06.02 is available.');
  });
}

ProviderContainer _container({
  required ToolDiscovery discovery,
  AppSettingsRepository? settingsRepository,
  YtDlpUpdateService? updateService,
}) {
  return ProviderContainer(
    overrides: [
      toolDiscoveryProvider.overrideWithValue(discovery),
      bundledToolInstallerProvider.overrideWithValue(
        const _FakeBundledToolInstaller(),
      ),
      appSettingsRepositoryProvider.overrideWithValue(
        settingsRepository ?? _MemorySettingsRepository(),
      ),
      if (updateService != null)
        ytDlpUpdateServiceProvider.overrideWithValue(updateService),
    ],
  );
}

class _FakeToolDiscovery extends ToolDiscovery {
  ToolPathPreferences? lastPreferences;

  @override
  Future<ToolSet> inspect({
    ToolPathPreferences preferences = const ToolPathPreferences(),
  }) async {
    lastPreferences = preferences;
    final ytDlpPath = preferences.ytDlpPath ?? preferences.bundledYtDlpPath;

    return ToolSet(
      ytDlp: ToolInfo.available(
        path: ytDlpPath ?? '/system/yt-dlp',
        version: preferences.bundledYtDlpVersion ?? '2026.06.01',
        source: preferences.ytDlpPath == null
            ? ToolSource.bundled
            : ToolSource.custom,
      ),
      ffmpeg: ToolInfo.available(
        path:
            preferences.ffmpegPath ??
            preferences.bundledFfmpegPath ??
            '/system/ffmpeg',
        version: preferences.bundledFfmpegVersion ?? '8.1',
      ),
      ffprobe: ToolInfo.available(
        path:
            preferences.ffprobePath ??
            preferences.bundledFfprobePath ??
            '/system/ffprobe',
        version: preferences.bundledFfprobeVersion ?? '8.1',
      ),
    );
  }
}

class _FakeBundledToolInstaller extends BundledToolInstaller {
  const _FakeBundledToolInstaller();

  @override
  Future<BundledToolPaths> installCurrentPlatformTools() async {
    return const BundledToolPaths(
      ytDlp: '/bundled/yt-dlp',
      ytDlpVersion: '2026.06.01',
      ffmpeg: '/bundled/ffmpeg',
      ffmpegVersion: '8.1',
      ffprobe: '/bundled/ffprobe',
      ffprobeVersion: '8.1',
    );
  }
}

class _MemorySettingsRepository extends AppSettingsRepository {
  String? ytDlpPath;
  String? ffmpegPath;
  String? ffprobePath;
  String? concurrencyLimitName;

  @override
  Future<AppSettings> load() async {
    return AppSettings(
      ytDlpPath: ytDlpPath,
      ffmpegPath: ffmpegPath,
      ffprobePath: ffprobePath,
      concurrencyLimitName: concurrencyLimitName,
    );
  }

  @override
  Future<void> saveOutputDirectory(String outputDirectory) async {}

  @override
  Future<void> saveSelectedPreset(PresetDefinition preset) async {}

  @override
  Future<void> saveConcurrencyLimit(DownloadConcurrencyLimit limit) async {
    concurrencyLimitName = limit.name;
  }

  @override
  Future<void> saveToolPaths({
    String? ytDlpPath,
    String? ffmpegPath,
    String? ffprobePath,
  }) async {
    this.ytDlpPath = ytDlpPath;
    this.ffmpegPath = ffmpegPath;
    this.ffprobePath = ffprobePath;
  }

  @override
  Future<void> saveYtDlpPath(String? path) async {
    ytDlpPath = path;
  }

  @override
  Future<void> saveFfmpegPath(String? path) async {
    ffmpegPath = path;
  }

  @override
  Future<void> saveFfprobePath(String? path) async {
    ffprobePath = path;
  }
}

class _FakeYtDlpUpdateService extends YtDlpUpdateService {
  const _FakeYtDlpUpdateService();

  @override
  Future<YtDlpUpdateInfo> checkForUpdate({
    required String? currentVersion,
  }) async {
    return YtDlpUpdateInfo(
      currentVersion: currentVersion,
      latestVersion: '2026.06.02',
      updateAvailable: true,
    );
  }
}
