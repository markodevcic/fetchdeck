import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/download_models.dart';
import '../../../services/ffmpeg/ffmpeg_split_service.dart';
import '../../../services/tools/tool_discovery.dart';
import '../../downloads/application/download_controller.dart';
import '../../downloads/application/queue_controller.dart';

final splitSegmentExportControllerProvider =
    NotifierProvider<SplitSegmentExportController, SplitSegmentExportState>(
      SplitSegmentExportController.new,
    );

final splitSegmentExportServiceProvider =
    Provider.family<FfmpegSplitService, String>(
      (ref, executable) => FfmpegSplitService(executable: executable),
    );

class SplitSegmentExportState {
  const SplitSegmentExportState({this.activeJobIds = const {}});

  final Set<String> activeJobIds;

  bool isActive(String jobId) => activeJobIds.contains(jobId);
}

class SplitSegmentExportController extends Notifier<SplitSegmentExportState> {
  final _activeSessions = <String, FfmpegSplitSession>{};
  final _cancelledJobIds = <String>{};

  @override
  SplitSegmentExportState build() {
    ref.onDispose(_cancelAllSilently);
    return const SplitSegmentExportState();
  }

  Future<void> start({
    required DownloadJob job,
    required ToolSet toolSet,
    required String? outputDirectory,
    required DownloadStatusReporter reportStatus,
  }) async {
    if (_activeSessions.containsKey(job.id)) return;

    final ffmpegPath = toolSet.ffmpeg.path;
    if (!toolSet.ffmpeg.isAvailable || ffmpegPath == null) {
      reportStatus(
        'Cannot export split segments because ffmpeg was not found.',
      );
      return;
    }
    if (outputDirectory == null) {
      reportStatus('Choose an output folder before exporting split segments.');
      return;
    }

    final selectedSegments = _selectedManualSegments(job);
    final exportableSegments = _exportableManualSegments(job);
    if (selectedSegments.isEmpty) {
      reportStatus('Select at least one split segment before exporting.');
      return;
    }
    if (exportableSegments.isEmpty) {
      reportStatus('All selected split segments are already exported.');
      return;
    }

    final destination = _jobOutputDirectory(outputDirectory, job);
    final startedAt = DateTime.now();
    final alreadyCompletedCount = selectedSegments
        .where(_isExportedManualSegment)
        .length;
    _cancelledJobIds.remove(job.id);
    _replaceJob(
      job.id,
      job.copyWith(
        status: DownloadStatus.downloading,
        progress: _progressValue(
          completedUnits: alreadyCompletedCount.toDouble(),
          totalCount: selectedSegments.length,
        ),
        eta: 'Exporting $alreadyCompletedCount of ${selectedSegments.length}',
        error: null,
        outputPath: destination,
        startedAt: startedAt,
        clearDownloadedFilePath: true,
        clearDownloadedFileSize: true,
        clearCompletedAt: true,
        children: [
          for (final child in job.children)
            exportableSegments.any((segment) => segment.id == child.id)
                ? child.copyWith(
                    status: DownloadStatus.queued,
                    progress: 0,
                    clearError: true,
                    clearOutputPath: true,
                    clearDownloadedFilePath: true,
                    clearDownloadedFileSize: true,
                    clearStartedAt: true,
                    clearCompletedAt: true,
                  )
                : child,
        ],
        logLines: [
          ...job.logLines,
          if (job.status == DownloadStatus.failed) 'Retry started.',
          'Split export started.',
          'Output folder: $destination',
        ],
      ),
    );
    reportStatus('Exporting ${exportableSegments.length} split segments...');

    String? activeChildId;
    try {
      await Directory(destination).create(recursive: true);
      var completedCount = alreadyCompletedCount;
      for (var index = 0; index < exportableSegments.length; index += 1) {
        if (_cancelledJobIds.contains(job.id)) return;

        final segment = exportableSegments[index];
        activeChildId = segment.id;
        final sourceFilePath =
            segment.sourceFilePath ?? job.splitEditorSourcePath;
        final startTime = segment.startTime;
        final duration = segment.duration;
        if (sourceFilePath == null || sourceFilePath.trim().isEmpty) {
          throw const FfmpegSplitException(
            'Split source file is missing. Open the split editor again to prepare it.',
          );
        }
        if (!await File(sourceFilePath).exists()) {
          throw FfmpegSplitException(
            'Split source file no longer exists: $sourceFilePath',
          );
        }
        if (startTime == null ||
            duration == null ||
            duration <= Duration.zero) {
          throw FfmpegSplitException(
            'Segment "${segment.title}" is missing valid timing.',
          );
        }

        final outputPath = _segmentOutputPath(
          directory: destination,
          index: selectedSegments.indexWhere(
            (candidate) => candidate.id == segment.id,
          ),
          title: segment.title,
        );
        _updateChild(
          job.id,
          segment.id,
          (child) => child.copyWith(
            status: DownloadStatus.downloading,
            progress: 0.35,
            outputPath: destination,
            startedAt: DateTime.now(),
          ),
        );
        _updateJobProgress(
          job.id,
          progress: _progressValue(
            completedUnits: completedCount.toDouble(),
            totalCount: selectedSegments.length,
          ),
          label:
              'Exporting ${completedCount + 1} of ${selectedSegments.length}',
        );
        reportStatus('Exporting ${segment.title}...');

        final session = await ref
            .read(splitSegmentExportServiceProvider(ffmpegPath))
            .startExport(
              sourceFilePath: sourceFilePath,
              outputFilePath: outputPath,
              title: segment.title,
              startTime: startTime,
              duration: duration,
              fadeDuration: segment.fadeDuration ?? Duration.zero,
            );
        _activeSessions[job.id] = session;
        _syncActiveState();

        final progressSubscription = session.progress.listen((progress) {
          final clampedProgress = progress.clamp(0, 1).toDouble();
          _updateChild(
            job.id,
            segment.id,
            (child) => child.copyWith(
              status: DownloadStatus.downloading,
              progress: clampedProgress,
              outputPath: destination,
            ),
          );
          _updateJobProgress(
            job.id,
            progress: _progressValue(
              completedUnits: completedCount + clampedProgress,
              totalCount: selectedSegments.length,
            ),
            label:
                'Exporting ${completedCount + 1} of ${selectedSegments.length}',
          );
        });

        await session.completed.whenComplete(progressSubscription.cancel);
        if (_cancelledJobIds.contains(job.id)) return;
        _activeSessions.remove(job.id);
        _syncActiveState();

        completedCount += 1;
        final completedAt = DateTime.now();
        final fileSize = await _fileSize(outputPath);
        _updateChild(
          job.id,
          segment.id,
          (child) => child.copyWith(
            status: DownloadStatus.complete,
            progress: 1,
            outputPath: destination,
            downloadedFilePath: outputPath,
            downloadedFileSize: fileSize,
            completedAt: completedAt,
          ),
        );
        _updateJobProgress(
          job.id,
          progress: _progressValue(
            completedUnits: completedCount.toDouble(),
            totalCount: selectedSegments.length,
          ),
          label: '$completedCount of ${selectedSegments.length} exported',
        );
      }

      final completedAt = DateTime.now();
      _updateJob(
        job.id,
        (current) => current
            .copyWith(
              status: DownloadStatus.complete,
              progress: 1,
              eta: 'Complete',
              error: null,
              outputPath: destination,
              completedAt: completedAt,
            )
            .appendLog('Split export complete.'),
      );
      reportStatus('Split export complete: ${job.title}.');
    } on FfmpegSplitException catch (error) {
      _fail(
        job.id,
        destination,
        error.message,
        reportStatus,
        activeChildId: activeChildId ?? _currentDownloadingChildId(job.id),
      );
    } catch (error) {
      _fail(
        job.id,
        destination,
        'Unexpected split export error: $error',
        reportStatus,
        activeChildId: activeChildId ?? _currentDownloadingChildId(job.id),
      );
    } finally {
      _activeSessions.remove(job.id);
      _cancelledJobIds.remove(job.id);
      _syncActiveState();
    }
  }

  void cancel(DownloadJob job, {required DownloadStatusReporter reportStatus}) {
    _cancelledJobIds.add(job.id);
    final session = _activeSessions.remove(job.id);
    session?.cancel();
    _syncActiveState();
    _updateJob(
      job.id,
      (current) => current
          .copyWith(
            status: DownloadStatus.ready,
            eta: 'Cancelled',
            error: null,
            clearCompletedAt: true,
          )
          .appendLog('Split export cancelled.'),
    );
    reportStatus('Cancelled split export: ${job.title}.');
  }

  bool canExport(DownloadJob job) => _selectedManualSegments(job).isNotEmpty;

  void _fail(
    String jobId,
    String destination,
    String message,
    DownloadStatusReporter reportStatus, {
    String? activeChildId,
  }) {
    _activeSessions.remove(jobId);
    _syncActiveState();
    _updateJob(jobId, (current) {
      final completedCount = _selectedManualSegments(
        current,
      ).where((child) => child.status == DownloadStatus.complete).length;
      final selectedCount = _selectedManualSegments(current).length;
      return current
          .copyWith(
            status: DownloadStatus.failed,
            progress: selectedCount == 0
                ? current.progress
                : completedCount / selectedCount,
            eta: selectedCount == 0
                ? 'Failed'
                : '$completedCount of $selectedCount exported',
            error: message,
            outputPath: destination,
            completedAt: DateTime.now(),
            children: [
              for (final child in current.children)
                child.id == activeChildId
                    ? child.copyWith(
                        status: DownloadStatus.failed,
                        progress: 0,
                        error: message,
                        completedAt: DateTime.now(),
                      )
                    : child.kind == DownloadItemKind.manualSegment &&
                          child.isSelected &&
                          child.status == DownloadStatus.queued
                    ? child.copyWith(
                        status: DownloadStatus.ready,
                        progress: 0,
                        clearStartedAt: true,
                        clearCompletedAt: true,
                      )
                    : child,
            ],
          )
          .appendLog('Split export failed: $message');
    });
    reportStatus(message);
  }

  List<DownloadItem> _selectedManualSegments(DownloadJob job) {
    return job.children
        .where(
          (child) =>
              child.kind == DownloadItemKind.manualSegment && child.isSelected,
        )
        .toList(growable: false);
  }

  List<DownloadItem> _exportableManualSegments(DownloadJob job) {
    return _selectedManualSegments(job)
        .where((child) => !_isExportedManualSegment(child))
        .toList(growable: false);
  }

  bool _isExportedManualSegment(DownloadItem child) {
    final path = child.downloadedFilePath;
    return child.status == DownloadStatus.complete &&
        path != null &&
        path.trim().isNotEmpty &&
        File(path).existsSync();
  }

  String? _currentDownloadingChildId(String jobId) {
    final jobs = ref.read(queueControllerProvider).jobs;
    for (final job in jobs) {
      if (job.id != jobId) continue;
      for (final child in job.children) {
        if (child.kind == DownloadItemKind.manualSegment &&
            child.status == DownloadStatus.downloading) {
          return child.id;
        }
      }
    }
    return null;
  }

  void _replaceJob(String id, DownloadJob replacement) {
    ref.read(queueControllerProvider.notifier).replace(id, replacement);
  }

  void _updateJob(String id, DownloadJob Function(DownloadJob current) update) {
    ref.read(queueControllerProvider.notifier).update(id, update);
  }

  void _updateChild(
    String jobId,
    String childId,
    DownloadItem Function(DownloadItem child) update,
  ) {
    _updateJob(
      jobId,
      (job) => job.copyWith(
        children: [
          for (final child in job.children)
            child.id == childId ? update(child) : child,
        ],
      ),
    );
  }

  void _updateJobProgress(
    String jobId, {
    required double progress,
    required String label,
  }) {
    _updateJob(
      jobId,
      (job) => job.copyWith(
        status: DownloadStatus.downloading,
        progress: progress,
        eta: label,
      ),
    );
  }

  double _progressValue({
    required double completedUnits,
    required int totalCount,
  }) {
    if (totalCount <= 0) return 0;
    if (completedUnits <= 0) return 0.04;
    return (completedUnits / totalCount).clamp(0.04, 0.98).toDouble();
  }

  void _cancelAllSilently() {
    for (final session in _activeSessions.values) {
      session.cancel();
    }
    _activeSessions.clear();
    _cancelledJobIds.clear();
  }

  void _syncActiveState() {
    state = SplitSegmentExportState(
      activeJobIds: Set.unmodifiable(_activeSessions.keys),
    );
  }

  Future<int?> _fileSize(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return file.length();
    } on FileSystemException {
      return null;
    }
  }

  String _jobOutputDirectory(String baseDirectory, DownloadJob job) {
    final separator = Platform.pathSeparator;
    final normalizedBase = baseDirectory.endsWith(separator)
        ? baseDirectory.substring(0, baseDirectory.length - 1)
        : baseDirectory;
    return '$normalizedBase$separator${_safeFolderName(job.title)}';
  }

  String _segmentOutputPath({
    required String directory,
    required int index,
    required String title,
  }) {
    final separator = Platform.pathSeparator;
    final prefix = (index + 1).toString().padLeft(2, '0');
    return '$directory$separator$prefix - ${_safeFolderName(title)}.mp3';
  }

  String _safeFolderName(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final fallback = sanitized.isEmpty ? 'Track' : sanitized;
    return fallback.length <= 80 ? fallback : fallback.substring(0, 80).trim();
  }
}
