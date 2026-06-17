import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/download_models.dart';
import '../../../services/files/file_actions_service.dart';
import '../../downloads/application/analysis_controller.dart';
import '../../downloads/application/download_controller.dart';
import '../../downloads/application/queue_controller.dart';
import '../../settings/application/app_settings_controller.dart';
import '../../settings/application/download_concurrency_limit.dart';
import '../../settings/application/tool_controller.dart';
import '../../settings/application/tool_kind.dart';
import '../../split_editor/application/split_segment_export_controller.dart';
import '../../split_editor/application/split_source_controller.dart';
import 'navigation_controller.dart';
import 'status_controller.dart';
import '../../../services/yt_dlp/yt_dlp_authentication.dart';

final workbenchActionsProvider = Provider<WorkbenchActions>(
  (ref) => WorkbenchActions(ref),
);

class WorkbenchActions {
  const WorkbenchActions(this.ref);

  final Ref ref;

  Future<void> bootstrap() async {
    final settings = await ref
        .read(appSettingsControllerProvider.notifier)
        .load(reportStatus: setStatus);
    await loadQueue();
    final inspectedTools = await ref
        .read(toolControllerProvider.notifier)
        .inspect(settings: settings, reportStatus: setStatus);
    if (inspectedTools.ytDlp.isAvailable) {
      unawaited(checkYtDlpUpdate(automatic: true));
    }
  }

  void selectSection(String section) {
    ref.read(navigationControllerProvider.notifier).select(section);
    ref.read(queueControllerProvider.notifier).ensureVisibleSelection();
  }

  Future<void> loadQueue() async {
    final restoredCount = await ref
        .read(queueControllerProvider.notifier)
        .load();
    if (restoredCount > 0) {
      setStatus('Restored $restoredCount saved jobs.');
    }
  }

  Future<void> setOutputDirectory(String outputDirectory) {
    return ref
        .read(appSettingsControllerProvider.notifier)
        .setOutputDirectory(
          outputDirectory: outputDirectory,
          reportStatus: setStatus,
        )
        .then((_) => reconcileQueueFromDisk());
  }

  void reconcileQueueFromDisk() {
    final activeDownloads = ref.read(downloadControllerProvider).activeJobIds;
    final activeExports = ref
        .read(splitSegmentExportControllerProvider)
        .activeJobIds;
    if (activeDownloads.isNotEmpty || activeExports.isNotEmpty) return;

    ref.read(queueControllerProvider.notifier).reconcileLocalFiles();
  }

  Future<void> setConcurrencyLimit(DownloadConcurrencyLimit limit) {
    return ref
        .read(appSettingsControllerProvider.notifier)
        .setConcurrencyLimit(limit: limit, reportStatus: setStatus);
  }

  Future<void> setAuthentication(YtDlpAuthentication authentication) {
    return ref
        .read(appSettingsControllerProvider.notifier)
        .setAuthentication(
          authentication: authentication,
          reportStatus: setStatus,
        );
  }

  Future<void> setSelectedPreset(PresetDefinition preset) {
    return ref
        .read(appSettingsControllerProvider.notifier)
        .setSelectedPreset(preset);
  }

  Future<void> createCustomPreset(PresetDefinition preset) {
    return ref
        .read(appSettingsControllerProvider.notifier)
        .createCustomPreset(preset: preset, reportStatus: setStatus);
  }

  Future<void> deleteCustomPreset(PresetDefinition preset) {
    return ref
        .read(appSettingsControllerProvider.notifier)
        .deleteCustomPreset(preset: preset, reportStatus: setStatus);
  }

  Future<void> recheckTools() {
    return ref
        .read(toolControllerProvider.notifier)
        .inspectCurrent(reportStatus: setStatus);
  }

  Future<void> checkYtDlpUpdate({bool automatic = false}) {
    return ref
        .read(toolControllerProvider.notifier)
        .checkYtDlpUpdate(automatic: automatic, reportStatus: setStatus);
  }

  Future<void> installYtDlpUpdate() {
    return ref
        .read(toolControllerProvider.notifier)
        .installYtDlpUpdate(reportStatus: setStatus);
  }

  void skipYtDlpUpdate() {
    ref
        .read(toolControllerProvider.notifier)
        .skipYtDlpUpdate(reportStatus: setStatus);
  }

  Future<void> setToolPath({required ToolKind tool, required String path}) {
    return ref
        .read(toolControllerProvider.notifier)
        .setToolPath(tool: tool, path: path, reportStatus: setStatus);
  }

  Future<void> clearToolPath(ToolKind tool) {
    return ref
        .read(toolControllerProvider.notifier)
        .clearToolPath(tool: tool, reportStatus: setStatus);
  }

  Future<bool> analyzeUrl(String url) async {
    if (ref.read(toolControllerProvider).isInspecting ||
        ref.read(appSettingsControllerProvider).isLoading) {
      setStatus('Still checking local tools. Try again in a moment.');
      return false;
    }

    return ref
        .read(analysisControllerProvider.notifier)
        .analyze(
          url: url,
          preset: ref.read(appSettingsControllerProvider).activePreset,
          toolSet: ref.read(toolControllerProvider).toolSet,
          authentication: ref
              .read(appSettingsControllerProvider)
              .authentication,
          reportStatus: setStatus,
          cannotUseYtDlpMessage: cannotUseYtDlpMessage,
        );
  }

  Future<void> startVisibleDownloads() {
    final settings = ref.read(appSettingsControllerProvider);
    ref.read(queueControllerProvider.notifier).reconcileLocalFiles();
    final jobs = ref.read(queueControllerProvider).visibleJobs();
    final splitJobs = jobs.where(_hasSelectedManualSegments).toList();
    final regularJobs = jobs
        .where((job) => !_hasSelectedManualSegments(job))
        .toList();

    for (final job in splitJobs) {
      unawaited(
        ref
            .read(splitSegmentExportControllerProvider.notifier)
            .start(
              job: job,
              toolSet: ref.read(toolControllerProvider).toolSet,
              outputDirectory: settings.outputDirectory,
              reportStatus: setStatus,
            ),
      );
    }

    return ref
        .read(downloadControllerProvider.notifier)
        .startAll(
          jobs: regularJobs,
          toolSet: ref.read(toolControllerProvider).toolSet,
          outputDirectory: settings.outputDirectory,
          concurrencyLimit: settings.concurrencyLimit,
          authentication: settings.authentication,
          reportStatus: setStatus,
          cannotUseYtDlpMessage: cannotUseYtDlpMessage,
        );
  }

  Future<void> startDownload(DownloadJob job) {
    final reconciledJob = ref
        .read(queueControllerProvider.notifier)
        .reconcileLocalFilesForJob(job);
    if (!identical(reconciledJob, job)) {
      setStatus('Updated ${reconciledJob.title} from files on disk.');
    }

    if (_hasSelectedManualSegments(reconciledJob)) {
      return ref
          .read(splitSegmentExportControllerProvider.notifier)
          .start(
            job: reconciledJob,
            toolSet: ref.read(toolControllerProvider).toolSet,
            outputDirectory: ref
                .read(appSettingsControllerProvider)
                .outputDirectory,
            reportStatus: setStatus,
          );
    }

    return ref
        .read(downloadControllerProvider.notifier)
        .start(
          job: reconciledJob,
          toolSet: ref.read(toolControllerProvider).toolSet,
          outputDirectory: ref
              .read(appSettingsControllerProvider)
              .outputDirectory,
          authentication: ref
              .read(appSettingsControllerProvider)
              .authentication,
          reportStatus: setStatus,
          cannotUseYtDlpMessage: cannotUseYtDlpMessage,
        );
  }

  Future<void> retryJob(DownloadJob job) {
    final reconciledJob = ref
        .read(queueControllerProvider.notifier)
        .reconcileLocalFilesForJob(job);
    if (!identical(reconciledJob, job)) {
      setStatus('Updated ${reconciledJob.title} from files on disk.');
    }

    if (reconciledJob.mediaInfo == null) {
      return ref
          .read(analysisControllerProvider.notifier)
          .retry(
            job: reconciledJob,
            toolSet: ref.read(toolControllerProvider).toolSet,
            authentication: ref
                .read(appSettingsControllerProvider)
                .authentication,
            reportStatus: setStatus,
            cannotUseYtDlpMessage: cannotUseYtDlpMessage,
          );
    }

    return startDownload(reconciledJob);
  }

  Future<DownloadJob?> prepareSplitSource(DownloadJob job) {
    final reconciledJob = ref
        .read(queueControllerProvider.notifier)
        .reconcileLocalFilesForJob(job);
    final settings = ref.read(appSettingsControllerProvider);
    return ref
        .read(splitSourceControllerProvider.notifier)
        .prepare(
          job: reconciledJob,
          toolSet: ref.read(toolControllerProvider).toolSet,
          outputDirectory: settings.outputDirectory,
          authentication: settings.authentication,
          reportStatus: setStatus,
          cannotUseYtDlpMessage: cannotUseYtDlpMessage,
        );
  }

  void cancelDownload(DownloadJob job) {
    if (ref.read(splitSegmentExportControllerProvider).isActive(job.id)) {
      ref
          .read(splitSegmentExportControllerProvider.notifier)
          .cancel(job, reportStatus: setStatus);
      return;
    }

    ref
        .read(downloadControllerProvider.notifier)
        .cancel(job, reportStatus: setStatus);
  }

  Future<void> revealOutput(DownloadJob job) async {
    final path =
        job.bestOutputPath ??
        ref.read(appSettingsControllerProvider).outputDirectory;
    if (path == null) {
      setStatus('No output folder is available for ${job.title}.');
      return;
    }

    try {
      await ref.read(fileActionsServiceProvider).reveal(path);
      setStatus('Opened output for ${job.title}.');
    } on FileActionException catch (error) {
      setStatus(error.message);
    }
  }

  Future<void> openFullDiskAccessSettings() async {
    try {
      await ref.read(fileActionsServiceProvider).openFullDiskAccessSettings();
      setStatus('Opened macOS Full Disk Access settings.');
    } on FileActionException catch (error) {
      setStatus(error.message);
    }
  }

  void removeJob(DownloadJob job) {
    ref.read(downloadControllerProvider.notifier).cancelIfActive(job);
    ref.read(queueControllerProvider.notifier).remove(job);
    setStatus('Removed ${job.title}.');
  }

  void setJobFormat(DownloadJob job, String? formatId) {
    ref
        .read(queueControllerProvider.notifier)
        .update(
          job.id,
          (current) => current.copyWith(
            selectedFormatId: formatId,
            clearSelectedFormat: formatId == null,
          ),
        );
    setStatus(
      formatId == null
          ? 'Using preset format selection for ${job.title}.'
          : 'Selected format $formatId for ${job.title}.',
    );
  }

  void setStatus(String message) {
    ref.read(statusControllerProvider.notifier).setMessage(message);
  }

  String cannotUseYtDlpMessage() {
    final ytDlp = ref.read(toolControllerProvider).toolSet.ytDlp;
    final path = ytDlp.path;
    if (path != null) {
      final detail = ytDlp.error == null ? '' : ' ${ytDlp.error}';
      return 'Cannot analyze yet: yt-dlp could not run.$detail';
    }

    return 'Cannot analyze yet because yt-dlp was not found.';
  }

  bool _hasSelectedManualSegments(DownloadJob job) {
    return job.children.any(
      (child) =>
          child.kind == DownloadItemKind.manualSegment && child.isSelected,
    );
  }
}
