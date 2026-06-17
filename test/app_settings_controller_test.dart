import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/features/settings/application/app_settings_controller.dart';
import 'package:yt_dlp_desktop/features/settings/application/download_concurrency_limit.dart';
import 'package:yt_dlp_desktop/models/download_models.dart';
import 'package:yt_dlp_desktop/services/presets/custom_preset_repository.dart';
import 'package:yt_dlp_desktop/services/settings/app_settings_repository.dart';
import 'package:yt_dlp_desktop/services/yt_dlp/yt_dlp_authentication.dart';

void main() {
  test('load restores custom presets and saves missing defaults', () async {
    final settingsRepository = _MemorySettingsRepository();
    final customRepository = _MemoryCustomPresetRepository(
      savedPresets: [_customPreset],
    );
    final container = _container(
      settingsRepository: settingsRepository,
      customRepository: customRepository,
    );
    addTearDown(container.dispose);

    final statuses = <String>[];
    await container
        .read(appSettingsControllerProvider.notifier)
        .load(reportStatus: statuses.add);

    final state = container.read(appSettingsControllerProvider);
    expect(state.outputDirectory, '/downloads/Fetchdeck');
    expect(state.concurrencyLimit, DownloadConcurrencyLimit.one);
    expect(state.availablePresets, contains(_customPreset));
    expect(state.activePreset, PresetDefinition.defaultPreset);
    expect(settingsRepository.outputDirectory, '/downloads/Fetchdeck');
    expect(
      settingsRepository.selectedPresetId,
      PresetDefinition.defaultPreset.id,
    );
    expect(
      settingsRepository.concurrencyLimitName,
      DownloadConcurrencyLimit.one.name,
    );
    expect(settingsRepository.useBrowserCookies, isFalse);
    expect(settingsRepository.browserCookieSourceName, 'chrome');
    expect(statuses, ['Loading saved settings...', 'Settings loaded.']);
  });

  test('createCustomPreset stores custom preset and selects it', () async {
    final settingsRepository = _MemorySettingsRepository();
    final customRepository = _MemoryCustomPresetRepository();
    final container = _container(
      settingsRepository: settingsRepository,
      customRepository: customRepository,
    );
    addTearDown(container.dispose);

    final statuses = <String>[];
    await container
        .read(appSettingsControllerProvider.notifier)
        .createCustomPreset(preset: _customPreset, reportStatus: statuses.add);

    final state = container.read(appSettingsControllerProvider);
    expect(state.activePreset, _customPreset);
    expect(customRepository.savedPresets, contains(_customPreset));
    expect(settingsRepository.selectedPresetId, _customPreset.id);
    expect(statuses.single, 'Created preset Custom MP3.');
  });

  test('deleteCustomPreset removes it and falls back when selected', () async {
    final settingsRepository = _MemorySettingsRepository();
    final customRepository = _MemoryCustomPresetRepository(
      savedPresets: [_customPreset],
    );
    final container = _container(
      settingsRepository: settingsRepository,
      customRepository: customRepository,
    );
    addTearDown(container.dispose);

    final statuses = <String>[];
    await container
        .read(appSettingsControllerProvider.notifier)
        .createCustomPreset(preset: _customPreset, reportStatus: statuses.add);
    await container
        .read(appSettingsControllerProvider.notifier)
        .deleteCustomPreset(preset: _customPreset, reportStatus: statuses.add);

    final state = container.read(appSettingsControllerProvider);
    expect(state.availablePresets, isNot(contains(_customPreset)));
    expect(state.activePreset, PresetDefinition.defaultPreset);
    expect(customRepository.savedPresets, isNot(contains(_customPreset)));
    expect(
      settingsRepository.selectedPresetId,
      PresetDefinition.defaultPreset.id,
    );
    expect(statuses.last, 'Deleted preset Custom MP3.');
  });

  test('setOutputDirectory saves selected folder', () async {
    final settingsRepository = _MemorySettingsRepository();
    final container = _container(settingsRepository: settingsRepository);
    addTearDown(container.dispose);

    final statuses = <String>[];
    await container
        .read(appSettingsControllerProvider.notifier)
        .setOutputDirectory(
          outputDirectory: '/tmp/media',
          reportStatus: statuses.add,
        );

    expect(
      container.read(appSettingsControllerProvider).outputDirectory,
      '/tmp/media',
    );
    expect(settingsRepository.outputDirectory, '/tmp/media');
    expect(statuses.single, 'Output folder set to /tmp/media.');
  });

  test('setConcurrencyLimit saves selected limit', () async {
    final settingsRepository = _MemorySettingsRepository();
    final container = _container(settingsRepository: settingsRepository);
    addTearDown(container.dispose);

    final statuses = <String>[];
    await container
        .read(appSettingsControllerProvider.notifier)
        .setConcurrencyLimit(
          limit: DownloadConcurrencyLimit.three,
          reportStatus: statuses.add,
        );

    expect(
      container.read(appSettingsControllerProvider).concurrencyLimit,
      DownloadConcurrencyLimit.three,
    );
    expect(settingsRepository.concurrencyLimitName, 'three');
    expect(statuses.single, 'Download concurrency set to 3 at a time.');
  });

  test('setAuthentication saves browser cookie source', () async {
    final settingsRepository = _MemorySettingsRepository();
    final container = _container(settingsRepository: settingsRepository);
    addTearDown(container.dispose);

    const authentication = YtDlpAuthentication(
      useBrowserCookies: true,
      browser: BrowserCookieSource.chrome,
      browserProfile: 'Profile 1',
    );

    final statuses = <String>[];
    await container
        .read(appSettingsControllerProvider.notifier)
        .setAuthentication(
          authentication: authentication,
          reportStatus: statuses.add,
        );

    expect(
      container.read(appSettingsControllerProvider).authentication,
      authentication,
    );
    expect(settingsRepository.useBrowserCookies, isTrue);
    expect(settingsRepository.browserCookieSourceName, 'chrome');
    expect(settingsRepository.browserCookieProfile, 'Profile 1');
    expect(statuses.single, 'Browser cookies enabled from Chrome (Profile 1).');
  });
}

ProviderContainer _container({
  _MemorySettingsRepository? settingsRepository,
  _MemoryCustomPresetRepository? customRepository,
}) {
  return ProviderContainer(
    overrides: [
      appSettingsRepositoryProvider.overrideWithValue(
        settingsRepository ?? _MemorySettingsRepository(),
      ),
      customPresetRepositoryProvider.overrideWithValue(
        customRepository ?? _MemoryCustomPresetRepository(),
      ),
      defaultOutputDirectoryResolverProvider.overrideWithValue(
        const _FakeDefaultOutputDirectoryResolver(),
      ),
    ],
  );
}

const _customPreset = PresetDefinition(
  id: 'custom:mp3',
  label: 'Custom MP3',
  description: 'Custom audio preset.',
  commandSummary: '-x --audio-format mp3',
  arguments: ['-x', '--audio-format', 'mp3'],
  isBuiltIn: false,
);

class _MemorySettingsRepository extends AppSettingsRepository {
  String? outputDirectory;
  String? selectedPresetId;
  String? ytDlpPath;
  String? ffmpegPath;
  String? ffprobePath;
  String? concurrencyLimitName;
  bool? useBrowserCookies;
  String? browserCookieSourceName;
  String? browserCookieProfile;

  @override
  Future<AppSettings> load() async {
    return AppSettings(
      outputDirectory: outputDirectory,
      selectedPresetId: selectedPresetId,
      ytDlpPath: ytDlpPath,
      ffmpegPath: ffmpegPath,
      ffprobePath: ffprobePath,
      concurrencyLimitName: concurrencyLimitName,
      useBrowserCookies: useBrowserCookies,
      browserCookieSourceName: browserCookieSourceName,
      browserCookieProfile: browserCookieProfile,
    );
  }

  @override
  Future<void> saveOutputDirectory(String outputDirectory) async {
    this.outputDirectory = outputDirectory;
  }

  @override
  Future<void> saveSelectedPreset(PresetDefinition preset) async {
    selectedPresetId = preset.id;
  }

  @override
  Future<void> saveConcurrencyLimit(DownloadConcurrencyLimit limit) async {
    concurrencyLimitName = limit.name;
  }

  @override
  Future<void> saveAuthentication(YtDlpAuthentication authentication) async {
    useBrowserCookies = authentication.useBrowserCookies;
    browserCookieSourceName = authentication.browser.name;
    browserCookieProfile = authentication.browserProfile;
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

class _MemoryCustomPresetRepository extends CustomPresetRepository {
  _MemoryCustomPresetRepository({List<PresetDefinition>? savedPresets})
    : savedPresets = [...?savedPresets];

  final List<PresetDefinition> savedPresets;

  @override
  Future<List<PresetDefinition>> load() async => savedPresets;

  @override
  Future<void> save(List<PresetDefinition> presets) async {
    savedPresets
      ..clear()
      ..addAll(presets.where((preset) => !preset.isBuiltIn));
  }
}

class _FakeDefaultOutputDirectoryResolver
    extends DefaultOutputDirectoryResolver {
  const _FakeDefaultOutputDirectoryResolver();

  @override
  Future<String> resolve() async => '/downloads/Fetchdeck';
}
