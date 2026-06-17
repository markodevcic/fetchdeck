import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/settings/app_settings_repository.dart';
import '../../../services/tools/bundled_tool_installer.dart';
import '../../../services/tools/tool_discovery.dart';
import '../../../services/tools/yt_dlp_update_service.dart';
import 'app_settings_controller.dart';
import 'tool_kind.dart';

final toolDiscoveryProvider = Provider<ToolDiscovery>((ref) => ToolDiscovery());

final bundledToolInstallerProvider = Provider<BundledToolInstaller>(
  (ref) => const BundledToolInstaller(),
);

final ytDlpUpdateServiceProvider = Provider<YtDlpUpdateService>(
  (ref) => const YtDlpUpdateService(),
);

final toolControllerProvider =
    NotifierProvider<ToolController, ToolControllerState>(ToolController.new);

typedef ToolStatusReporter = void Function(String message);

const _unchanged = Object();

class ToolControllerState {
  const ToolControllerState({
    this.toolSet = const ToolSet.empty(),
    this.isInspecting = false,
    this.ytDlpPath,
    this.ffmpegPath,
    this.ffprobePath,
    this.updateInfo,
    this.isCheckingYtDlpUpdate = false,
    this.isUpdatingYtDlp = false,
    this.updateDismissed = false,
  });

  final ToolSet toolSet;
  final bool isInspecting;
  final String? ytDlpPath;
  final String? ffmpegPath;
  final String? ffprobePath;
  final YtDlpUpdateInfo? updateInfo;
  final bool isCheckingYtDlpUpdate;
  final bool isUpdatingYtDlp;
  final bool updateDismissed;

  String? visiblePath(ToolKind tool) {
    return switch (tool) {
      ToolKind.ytDlp => ytDlpPath ?? toolSet.ytDlp.path,
      ToolKind.ffmpeg => ffmpegPath ?? toolSet.ffmpeg.path,
      ToolKind.ffprobe => ffprobePath ?? toolSet.ffprobe.path,
    };
  }

  ToolControllerState copyWith({
    ToolSet? toolSet,
    bool? isInspecting,
    Object? ytDlpPath = _unchanged,
    Object? ffmpegPath = _unchanged,
    Object? ffprobePath = _unchanged,
    Object? updateInfo = _unchanged,
    bool? isCheckingYtDlpUpdate,
    bool? isUpdatingYtDlp,
    bool? updateDismissed,
  }) {
    return ToolControllerState(
      toolSet: toolSet ?? this.toolSet,
      isInspecting: isInspecting ?? this.isInspecting,
      ytDlpPath: ytDlpPath == _unchanged
          ? this.ytDlpPath
          : ytDlpPath as String?,
      ffmpegPath: ffmpegPath == _unchanged
          ? this.ffmpegPath
          : ffmpegPath as String?,
      ffprobePath: ffprobePath == _unchanged
          ? this.ffprobePath
          : ffprobePath as String?,
      updateInfo: updateInfo == _unchanged
          ? this.updateInfo
          : updateInfo as YtDlpUpdateInfo?,
      isCheckingYtDlpUpdate:
          isCheckingYtDlpUpdate ?? this.isCheckingYtDlpUpdate,
      isUpdatingYtDlp: isUpdatingYtDlp ?? this.isUpdatingYtDlp,
      updateDismissed: updateDismissed ?? this.updateDismissed,
    );
  }
}

class ToolController extends Notifier<ToolControllerState> {
  @override
  ToolControllerState build() => const ToolControllerState();

  Future<ToolSet> inspect({
    required AppSettings settings,
    required ToolStatusReporter reportStatus,
  }) async {
    state = state.copyWith(
      isInspecting: true,
      ytDlpPath: settings.ytDlpPath,
      ffmpegPath: settings.ffmpegPath,
      ffprobePath: settings.ffprobePath,
    );
    reportStatus('Checking local tools...');

    final bundledTools = await ref
        .read(bundledToolInstallerProvider)
        .installCurrentPlatformTools();
    final inspectedTools = await ref
        .read(toolDiscoveryProvider)
        .inspect(
          preferences: ToolPathPreferences(
            ytDlpPath: settings.ytDlpPath,
            ffmpegPath: settings.ffmpegPath,
            ffprobePath: settings.ffprobePath,
            bundledYtDlpPath: bundledTools.ytDlp,
            bundledYtDlpVersion: bundledTools.ytDlpVersion,
            bundledFfmpegPath: bundledTools.ffmpeg,
            bundledFfmpegVersion: bundledTools.ffmpegVersion,
            bundledFfprobePath: bundledTools.ffprobe,
            bundledFfprobeVersion: bundledTools.ffprobeVersion,
          ),
        );

    state = state.copyWith(toolSet: inspectedTools, isInspecting: false);
    reportStatus(
      inspectedTools.ytDlp.isAvailable
          ? 'Ready. yt-dlp found at ${inspectedTools.ytDlp.path}.'
          : _missingYtDlpMessage(inspectedTools.ytDlp),
    );
    return inspectedTools;
  }

  Future<ToolSet> inspectCurrent({
    required ToolStatusReporter reportStatus,
  }) async {
    return inspect(
      settings: AppSettings(
        ytDlpPath: state.ytDlpPath,
        ffmpegPath: state.ffmpegPath,
        ffprobePath: state.ffprobePath,
      ),
      reportStatus: reportStatus,
    );
  }

  Future<void> setToolPath({
    required ToolKind tool,
    required String? path,
    required ToolStatusReporter reportStatus,
  }) async {
    final repository = ref.read(appSettingsRepositoryProvider);
    switch (tool) {
      case ToolKind.ytDlp:
        await repository.saveYtDlpPath(path);
        state = state.copyWith(ytDlpPath: path);
      case ToolKind.ffmpeg:
        await repository.saveFfmpegPath(path);
        state = state.copyWith(ffmpegPath: path);
      case ToolKind.ffprobe:
        await repository.saveFfprobePath(path);
        state = state.copyWith(ffprobePath: path);
    }
    await inspectCurrent(reportStatus: reportStatus);
  }

  Future<void> clearToolPath({
    required ToolKind tool,
    required ToolStatusReporter reportStatus,
  }) async {
    await setToolPath(tool: tool, path: null, reportStatus: reportStatus);
  }

  Future<void> checkYtDlpUpdate({
    bool automatic = false,
    required ToolStatusReporter reportStatus,
  }) async {
    if (state.isCheckingYtDlpUpdate || state.isUpdatingYtDlp) return;

    state = state.copyWith(isCheckingYtDlpUpdate: true, updateDismissed: false);
    if (!automatic) {
      reportStatus('Checking for yt-dlp updates...');
    }

    try {
      final updateInfo = await ref
          .read(ytDlpUpdateServiceProvider)
          .checkForUpdate(currentVersion: state.toolSet.ytDlp.version);

      state = state.copyWith(updateInfo: updateInfo);
      if (updateInfo.updateAvailable || !automatic) {
        reportStatus(
          updateInfo.updateAvailable
              ? 'yt-dlp ${updateInfo.latestVersion} is available.'
              : 'yt-dlp is up to date (${updateInfo.latestVersion}).',
        );
      }
    } on YtDlpUpdateException catch (error) {
      if (!automatic) reportStatus(error.message);
    } catch (error) {
      if (!automatic) reportStatus('Could not check yt-dlp updates: $error');
    } finally {
      state = state.copyWith(isCheckingYtDlpUpdate: false);
    }
  }

  Future<void> installYtDlpUpdate({
    required ToolStatusReporter reportStatus,
  }) async {
    if (state.isUpdatingYtDlp) return;

    state = state.copyWith(isUpdatingYtDlp: true);
    reportStatus('Downloading yt-dlp update...');

    try {
      final result = await ref.read(ytDlpUpdateServiceProvider).installLatest();
      state = state.copyWith(
        updateInfo: YtDlpUpdateInfo(
          currentVersion: result.version,
          latestVersion: result.version,
          updateAvailable: false,
        ),
        updateDismissed: false,
      );
      reportStatus('Updated yt-dlp to ${result.version}. Re-checking tools...');
      await inspectCurrent(reportStatus: reportStatus);
    } on YtDlpUpdateException catch (error) {
      reportStatus(error.message);
    } catch (error) {
      reportStatus('Could not update yt-dlp: $error');
    } finally {
      state = state.copyWith(isUpdatingYtDlp: false);
    }
  }

  void skipYtDlpUpdate({required ToolStatusReporter reportStatus}) {
    state = state.copyWith(updateDismissed: true);
    reportStatus('Skipped yt-dlp update for now.');
  }

  String _missingYtDlpMessage(ToolInfo ytDlp) {
    final path = ytDlp.path;
    if (path != null) {
      final detail = ytDlp.error == null ? '' : ' ${ytDlp.error}';
      return 'yt-dlp could not run.$detail';
    }

    return 'yt-dlp was not found. Install it or place yt-dlp/yt-dlp_macos in Downloads, ~/.local/bin, /opt/homebrew/bin, or /usr/local/bin.';
  }
}
