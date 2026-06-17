import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../models/download_models.dart';
import '../../../services/presets/custom_preset_repository.dart';
import '../../../services/settings/app_settings_repository.dart';
import '../../../services/yt_dlp/yt_dlp_authentication.dart';
import 'download_concurrency_limit.dart';

final appSettingsRepositoryProvider = Provider<AppSettingsRepository>(
  (ref) => const AppSettingsRepository(),
);

final customPresetRepositoryProvider = Provider<CustomPresetRepository>(
  (ref) => const CustomPresetRepository(),
);

final defaultOutputDirectoryResolverProvider =
    Provider<DefaultOutputDirectoryResolver>(
      (ref) => const DefaultOutputDirectoryResolver(),
    );

final appSettingsControllerProvider =
    NotifierProvider<AppSettingsController, AppSettingsState>(
      AppSettingsController.new,
    );

typedef SettingsStatusReporter = void Function(String message);

class AppSettingsState {
  const AppSettingsState({
    this.presets = const [],
    this.selectedPreset,
    this.outputDirectory,
    this.concurrencyLimit = DownloadConcurrencyLimit.one,
    this.authentication = YtDlpAuthentication.none,
    this.isLoading = false,
  });

  final List<PresetDefinition> presets;
  final PresetDefinition? selectedPreset;
  final String? outputDirectory;
  final DownloadConcurrencyLimit concurrencyLimit;
  final YtDlpAuthentication authentication;
  final bool isLoading;

  List<PresetDefinition> get availablePresets {
    return presets.isEmpty ? PresetDefinition.builtIns : presets;
  }

  PresetDefinition get activePreset {
    return selectedPreset ?? PresetDefinition.defaultPreset;
  }

  AppSettingsState copyWith({
    List<PresetDefinition>? presets,
    PresetDefinition? selectedPreset,
    String? outputDirectory,
    DownloadConcurrencyLimit? concurrencyLimit,
    YtDlpAuthentication? authentication,
    bool? isLoading,
  }) {
    return AppSettingsState(
      presets: presets ?? this.presets,
      selectedPreset: selectedPreset ?? this.selectedPreset,
      outputDirectory: outputDirectory ?? this.outputDirectory,
      concurrencyLimit: concurrencyLimit ?? this.concurrencyLimit,
      authentication: authentication ?? this.authentication,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AppSettingsController extends Notifier<AppSettingsState> {
  @override
  AppSettingsState build() {
    return AppSettingsState(
      presets: PresetDefinition.builtIns,
      selectedPreset: PresetDefinition.defaultPreset,
    );
  }

  Future<AppSettings> load({
    required SettingsStatusReporter reportStatus,
  }) async {
    state = state.copyWith(isLoading: true);
    reportStatus('Loading saved settings...');

    final customPresets = await ref.read(customPresetRepositoryProvider).load();
    final presets = [...PresetDefinition.builtIns, ...customPresets];
    final settings = await ref.read(appSettingsRepositoryProvider).load();
    final defaultOutputDirectory = await ref
        .read(defaultOutputDirectoryResolverProvider)
        .resolve();

    final selectedPreset =
        _presetById(presets, settings.selectedPresetId) ??
        PresetDefinition.defaultPreset;
    final outputDirectory = settings.outputDirectory ?? defaultOutputDirectory;
    final concurrencyLimit = DownloadConcurrencyLimit.byName(
      settings.concurrencyLimitName,
    );
    final authentication = YtDlpAuthentication(
      useBrowserCookies: settings.useBrowserCookies ?? false,
      browser:
          BrowserCookieSource.byName(settings.browserCookieSourceName) ??
          BrowserCookieSource.chrome,
      browserProfile: settings.browserCookieProfile,
    );

    state = state.copyWith(
      presets: presets,
      selectedPreset: selectedPreset,
      outputDirectory: outputDirectory,
      concurrencyLimit: concurrencyLimit,
      authentication: authentication,
      isLoading: false,
    );
    reportStatus('Settings loaded.');

    final repository = ref.read(appSettingsRepositoryProvider);
    if (settings.outputDirectory == null) {
      await repository.saveOutputDirectory(defaultOutputDirectory);
    }
    if (settings.selectedPresetId == null) {
      await repository.saveSelectedPreset(selectedPreset);
    }
    if (settings.concurrencyLimitName == null) {
      await repository.saveConcurrencyLimit(concurrencyLimit);
    }
    if (settings.useBrowserCookies == null ||
        settings.browserCookieSourceName == null) {
      await repository.saveAuthentication(authentication);
    }

    return settings;
  }

  Future<void> setSelectedPreset(PresetDefinition preset) async {
    state = state.copyWith(selectedPreset: preset);
    await ref.read(appSettingsRepositoryProvider).saveSelectedPreset(preset);
  }

  Future<void> setOutputDirectory({
    required String outputDirectory,
    required SettingsStatusReporter reportStatus,
  }) async {
    state = state.copyWith(outputDirectory: outputDirectory);
    reportStatus('Output folder set to $outputDirectory.');
    await ref
        .read(appSettingsRepositoryProvider)
        .saveOutputDirectory(outputDirectory);
  }

  Future<void> setConcurrencyLimit({
    required DownloadConcurrencyLimit limit,
    required SettingsStatusReporter reportStatus,
  }) async {
    state = state.copyWith(concurrencyLimit: limit);
    reportStatus('Download concurrency set to ${limit.label}.');
    await ref.read(appSettingsRepositoryProvider).saveConcurrencyLimit(limit);
  }

  Future<void> setAuthentication({
    required YtDlpAuthentication authentication,
    required SettingsStatusReporter reportStatus,
  }) async {
    state = state.copyWith(authentication: authentication);
    reportStatus(
      authentication.useBrowserCookies
          ? 'Browser cookies enabled from ${_authenticationLabel(authentication)}.'
          : 'Browser cookies disabled.',
    );
    await ref
        .read(appSettingsRepositoryProvider)
        .saveAuthentication(authentication);
  }

  Future<void> createCustomPreset({
    required PresetDefinition preset,
    required SettingsStatusReporter reportStatus,
  }) async {
    final presets = [...state.availablePresets, preset];
    state = state.copyWith(presets: presets, selectedPreset: preset);
    reportStatus('Created preset ${preset.label}.');

    await ref.read(customPresetRepositoryProvider).save(presets);
    await ref.read(appSettingsRepositoryProvider).saveSelectedPreset(preset);
  }

  Future<void> deleteCustomPreset({
    required PresetDefinition preset,
    required SettingsStatusReporter reportStatus,
  }) async {
    if (preset.isBuiltIn) return;

    final presets = state.availablePresets
        .where((candidate) => candidate.id != preset.id)
        .toList(growable: false);
    final selectedPreset = state.activePreset.id == preset.id
        ? PresetDefinition.defaultPreset
        : state.activePreset;

    state = state.copyWith(presets: presets, selectedPreset: selectedPreset);
    reportStatus('Deleted preset ${preset.label}.');

    await ref.read(customPresetRepositoryProvider).save(presets);
    await ref
        .read(appSettingsRepositoryProvider)
        .saveSelectedPreset(selectedPreset);
  }

  PresetDefinition? _presetById(List<PresetDefinition> presets, String? id) {
    if (id == null) return null;
    for (final preset in presets) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  String _authenticationLabel(YtDlpAuthentication authentication) {
    final profile = authentication.browserProfile?.trim();
    if (profile == null || profile.isEmpty) return authentication.browser.label;
    return '${authentication.browser.label} ($profile)';
  }
}

class DefaultOutputDirectoryResolver {
  const DefaultOutputDirectoryResolver();

  Future<String> resolve() async {
    final downloads = await getDownloadsDirectory();
    final base = downloads?.path ?? Directory.current.path;
    return '$base/Fetchdeck';
  }
}
