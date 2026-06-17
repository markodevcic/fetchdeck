import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/download_models.dart';
import '../../../services/tools/tool_discovery.dart';
import '../../../services/yt_dlp/yt_dlp_authentication.dart';
import '../../../services/yt_dlp/yt_dlp_service.dart';
import '../../settings/application/download_concurrency_limit.dart';
import 'queue_controller.dart';

final downloadControllerProvider =
    NotifierProvider<DownloadController, DownloadControllerState>(
      DownloadController.new,
    );

final ytDlpDownloadServiceProvider = Provider.family<YtDlpService, String>(
  (ref, executable) => YtDlpService(executable: executable),
);

typedef DownloadStatusReporter = void Function(String message);

class DownloadControllerState {
  const DownloadControllerState({this.activeJobIds = const {}});

  final Set<String> activeJobIds;

  bool isActive(String jobId) => activeJobIds.contains(jobId);
}

class DownloadController extends Notifier<DownloadControllerState> {
  final _activeDownloads = <String, YtDlpDownloadSession>{};
  final _pendingDownloads = <_DownloadRequest>[];
  final _cancelledJobIds = <String>{};
  DownloadConcurrencyLimit _concurrencyLimit = DownloadConcurrencyLimit.one;

  @override
  DownloadControllerState build() {
    ref.onDispose(_cancelAllSilently);
    return const DownloadControllerState();
  }

  Future<void> startAll({
    required List<DownloadJob> jobs,
    required ToolSet toolSet,
    required String? outputDirectory,
    required DownloadConcurrencyLimit concurrencyLimit,
    required YtDlpAuthentication authentication,
    required DownloadStatusReporter reportStatus,
    required String Function() cannotUseYtDlpMessage,
  }) async {
    final executable = toolSet.ytDlp.path;
    if (!toolSet.ytDlp.isAvailable || executable == null) {
      reportStatus(cannotUseYtDlpMessage());
      return;
    }
    if (outputDirectory == null) {
      reportStatus('Choose an output folder before downloading.');
      return;
    }

    _concurrencyLimit = concurrencyLimit;
    final eligibleJobs = List<DownloadJob>.from(
      jobs,
    ).where((job) => _canQueue(job) && job.mediaInfo != null).toList();
    if (eligibleJobs.isEmpty) return;

    var queuedCount = 0;
    for (final job in eligibleJobs) {
      if (_activeDownloads.containsKey(job.id) ||
          _pendingDownloads.any((request) => request.job.id == job.id)) {
        continue;
      }

      final queuedJob = job
          .copyWith(
            status: DownloadStatus.queued,
            progress: 0,
            eta: 'Queued',
            error: null,
            clearStartedAt: true,
            clearCompletedAt: true,
            clearDownloadedFileSize: true,
          )
          .appendLog('Queued for download.');
      _replaceJob(job.id, queuedJob);
      _pendingDownloads.add(
        _DownloadRequest(
          job: queuedJob,
          toolSet: toolSet,
          outputDirectory: outputDirectory,
          authentication: authentication,
          reportStatus: reportStatus,
          cannotUseYtDlpMessage: cannotUseYtDlpMessage,
        ),
      );
      queuedCount += 1;
    }

    if (queuedCount > 0) {
      reportStatus(
        queuedCount == 1
            ? 'Queued 1 download.'
            : 'Queued $queuedCount downloads.',
      );
    }
    await _drainPendingDownloads();
  }

  Future<void> start({
    required DownloadJob job,
    required ToolSet toolSet,
    required String? outputDirectory,
    required YtDlpAuthentication authentication,
    required DownloadStatusReporter reportStatus,
    required String Function() cannotUseYtDlpMessage,
    bool useBrowserCookiesForAttempt = false,
  }) async {
    _cancelledJobIds.remove(job.id);
    if (_activeDownloads.containsKey(job.id) ||
        _pendingDownloads.any((request) => request.job.id == job.id)) {
      return;
    }

    final executable = toolSet.ytDlp.path;
    final baseDestination = outputDirectory;
    if (!toolSet.ytDlp.isAvailable || executable == null) {
      reportStatus(cannotUseYtDlpMessage());
      return;
    }
    if (baseDestination == null) {
      reportStatus('Choose an output folder before downloading.');
      return;
    }
    if (job.mediaInfo == null) {
      reportStatus('Analyze the URL before downloading.');
      return;
    }

    final startedAt = DateTime.now();
    final attemptAuthentication = useBrowserCookiesForAttempt
        ? authentication
        : YtDlpAuthentication.none;
    final destination = _jobOutputDirectory(baseDestination, job);

    final selectedChildren = _selectedDownloadableChildren(job);
    if (selectedChildren.isNotEmpty) {
      return _startSelectedChildren(
        job: job,
        children: selectedChildren,
        executable: executable,
        toolSet: toolSet,
        baseDestination: baseDestination,
        destination: destination,
        authentication: authentication,
        attemptAuthentication: attemptAuthentication,
        reportStatus: reportStatus,
        cannotUseYtDlpMessage: cannotUseYtDlpMessage,
      );
    }

    _replaceJob(
      job.id,
      job.copyWith(
        status: DownloadStatus.downloading,
        progress: 0.04,
        eta: 'Starting',
        error: null,
        outputPath: destination,
        startedAt: startedAt,
        clearDownloadedFilePath: true,
        clearDownloadedFileSize: true,
        clearCompletedAt: true,
        logLines: [
          ...job.logLines,
          if (job.status == DownloadStatus.failed) 'Retry started.',
          if (job.status == DownloadStatus.stopped)
            'Continuing stopped download.',
          'Download started.',
          if (useBrowserCookiesForAttempt)
            'Using browser cookies from ${authentication.browser.label}.',
          'Output folder: $destination',
        ],
      ),
    );
    reportStatus('Starting download: ${job.title}.');

    try {
      await Directory(destination).create(recursive: true);
      String? downloadedFilePath;
      var completedItems = 0;
      final totalItems = job.mediaInfo!.isPlaylist
          ? job.mediaInfo!.playlistCount
          : null;
      final session = await ref
          .read(ytDlpDownloadServiceProvider(executable))
          .startDownload(
            url: job.url,
            preset: job.preset,
            outputDirectory: destination,
            isPlaylist: job.mediaInfo!.isPlaylist,
            ffmpegPath: toolSet.ffmpeg.path,
            selectedFormatId: job.selectedFormatId,
            authentication: attemptAuthentication,
          );

      _activeDownloads[job.id] = session;
      _syncActiveState();

      session.events.listen((event) async {
        switch (event) {
          case DownloadProgressEvent(:final progress):
            if (!_activeDownloads.containsKey(job.id)) return;
            final percent = progress.percent;
            _updateJob(
              job.id,
              (current) => current.copyWith(
                status: DownloadStatus.downloading,
                progress: _nextProgressValue(
                  current: current.progress,
                  percent: percent,
                  completedItems: completedItems,
                  totalItems: totalItems,
                ),
                eta: progress.label,
                error: null,
                outputPath: destination,
                downloadedFilePath: downloadedFilePath,
              ),
            );
            reportStatus('${job.title}: ${progress.label}');
          case DownloadOutputEvent(:final path):
            downloadedFilePath = path;
            completedItems += 1;
            _updateJob(
              job.id,
              (current) => current
                  .copyWith(
                    outputPath: destination,
                    downloadedFilePath: path,
                    progress: _itemProgressValue(
                      completedItems: completedItems,
                      totalItems: totalItems,
                    ),
                    eta: totalItems == null
                        ? current.eta
                        : '$completedItems of $totalItems files',
                  )
                  .appendLog('Output file detected: $path'),
            );
          case DownloadCompleteEvent():
            if (_activeDownloads.remove(job.id) == null) return;
            _syncActiveState();
            final completedAt = DateTime.now();
            final downloadedFileSize = await _fileSize(downloadedFilePath);
            _updateJob(
              job.id,
              (current) => current
                  .copyWith(
                    status: DownloadStatus.complete,
                    progress: 1,
                    eta: 'Complete',
                    error: null,
                    outputPath: destination,
                    downloadedFilePath: downloadedFilePath,
                    downloadedFileSize: downloadedFileSize,
                    completedAt: completedAt,
                  )
                  .appendLog('Download complete.'),
            );
            reportStatus('Download complete: ${job.title}.');
            unawaited(_drainPendingDownloads());
          case DownloadErrorEvent(:final message):
            if (_activeDownloads.remove(job.id) == null) return;
            _syncActiveState();
            if (_shouldRetryWithBrowserCookies(
              message: message,
              configuredAuthentication: authentication,
              attemptAuthentication: attemptAuthentication,
            )) {
              await _retryWithBrowserCookies(
                jobId: job.id,
                toolSet: toolSet,
                outputDirectory: destination,
                authentication: authentication,
                reportStatus: reportStatus,
                cannotUseYtDlpMessage: cannotUseYtDlpMessage,
              );
              return;
            }
            final completedAt = DateTime.now();
            _updateJob(
              job.id,
              (current) => current
                  .copyWith(
                    status: DownloadStatus.failed,
                    eta: 'Failed',
                    error: message,
                    outputPath: destination,
                    downloadedFilePath: downloadedFilePath,
                    completedAt: completedAt,
                  )
                  .appendLog('Download failed: $message'),
            );
            reportStatus(message);
            unawaited(_drainPendingDownloads());
        }
      });
    } on YtDlpException catch (error) {
      if (_shouldRetryWithBrowserCookies(
        message: error.message,
        configuredAuthentication: authentication,
        attemptAuthentication: attemptAuthentication,
      )) {
        await _retryWithBrowserCookies(
          jobId: job.id,
          toolSet: toolSet,
          outputDirectory: destination,
          authentication: authentication,
          reportStatus: reportStatus,
          cannotUseYtDlpMessage: cannotUseYtDlpMessage,
        );
        return;
      }
      final completedAt = DateTime.now();
      _updateJob(
        job.id,
        (current) => current
            .copyWith(
              status: DownloadStatus.failed,
              eta: 'Failed',
              error: error.message,
              completedAt: completedAt,
            )
            .appendLog('Download failed: ${error.message}'),
      );
      reportStatus(error.message);
      unawaited(_drainPendingDownloads());
    } catch (error) {
      final completedAt = DateTime.now();
      _updateJob(
        job.id,
        (current) => current
            .copyWith(
              status: DownloadStatus.failed,
              eta: 'Failed',
              error: error.toString(),
              completedAt: completedAt,
            )
            .appendLog('Download failed: $error'),
      );
      reportStatus('Unexpected download error: $error');
      unawaited(_drainPendingDownloads());
    }
  }

  void cancel(DownloadJob job, {required DownloadStatusReporter reportStatus}) {
    final session = _activeDownloads.remove(job.id);
    final wasActive = session != null;
    if (wasActive) _cancelledJobIds.add(job.id);
    _pendingDownloads.removeWhere((request) => request.job.id == job.id);
    session?.cancel();
    _syncActiveState();
    _updateJob(
      job.id,
      (current) => current
          .copyWith(
            status: wasActive ? DownloadStatus.stopped : DownloadStatus.ready,
            eta: wasActive ? 'Stopped' : 'Cancelled',
            error: null,
            clearCompletedAt: true,
            children: _resetInterruptedChildren(current.children),
          )
          .appendLog(
            wasActive ? 'Download stopped by user.' : 'Download cancelled.',
          ),
    );
    reportStatus(
      wasActive
          ? 'Stopped download: ${job.title}.'
          : 'Cancelled queued download: ${job.title}.',
    );
    unawaited(_drainPendingDownloads());
  }

  void cancelIfActive(DownloadJob job) {
    _cancelledJobIds.add(job.id);
    final session = _activeDownloads.remove(job.id);
    session?.cancel();
    _pendingDownloads.removeWhere((request) => request.job.id == job.id);
    _syncActiveState();
  }

  Future<void> _startSelectedChildren({
    required DownloadJob job,
    required List<DownloadItem> children,
    required String executable,
    required ToolSet toolSet,
    required String baseDestination,
    required String destination,
    required YtDlpAuthentication authentication,
    required YtDlpAuthentication attemptAuthentication,
    required DownloadStatusReporter reportStatus,
    required String Function() cannotUseYtDlpMessage,
  }) async {
    final exportableChildren = children
        .where((child) => child.status != DownloadStatus.complete)
        .toList(growable: false);
    if (exportableChildren.isEmpty) {
      reportStatus('All selected child items are already downloaded.');
      return;
    }

    final startedAt = DateTime.now();
    final alreadyCompletedCount = children.length - exportableChildren.length;
    _replaceJob(
      job.id,
      job.copyWith(
        status: DownloadStatus.downloading,
        progress: _itemProgressValue(
          completedItems: alreadyCompletedCount,
          totalItems: children.length,
        ),
        eta: 'Downloading $alreadyCompletedCount of ${children.length}',
        error: null,
        outputPath: destination,
        startedAt: startedAt,
        clearDownloadedFilePath: true,
        clearDownloadedFileSize: true,
        clearCompletedAt: true,
        children: [
          for (final child in job.children)
            exportableChildren.any((candidate) => candidate.id == child.id)
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
          if (job.status == DownloadStatus.stopped)
            'Continuing stopped download.',
          'Selected child download started.',
          if (attemptAuthentication.useBrowserCookies)
            'Using browser cookies from ${authentication.browser.label}.',
          'Output folder: $destination',
        ],
      ),
    );
    reportStatus('Starting selected downloads: ${job.title}.');

    try {
      await Directory(destination).create(recursive: true);
      var completedCount = alreadyCompletedCount;
      for (final child in exportableChildren) {
        final childUrl = child.url ?? job.url;
        final section = _downloadSectionFor(child);
        final outputTemplate = child.kind == DownloadItemKind.chapter
            ? '${(children.indexWhere((item) => item.id == child.id) + 1).toString().padLeft(2, '0')} - ${_safeFolderName(child.title)}.%(ext)s'
            : null;
        String? downloadedFilePath;
        _updateChild(
          job.id,
          child.id,
          (current) => current.copyWith(
            status: DownloadStatus.downloading,
            progress: 0.04,
            outputPath: destination,
            startedAt: DateTime.now(),
          ),
        );
        _updateJobProgress(
          job.id,
          progress: _childProgressValue(
            completedCount: completedCount,
            currentChildProgress: 0,
            totalCount: children.length,
          ),
          label: 'Downloading ${completedCount + 1} of ${children.length}',
        );

        final session = await ref
            .read(ytDlpDownloadServiceProvider(executable))
            .startDownload(
              url: childUrl,
              preset: job.preset,
              outputDirectory: destination,
              isPlaylist: false,
              ffmpegPath: toolSet.ffmpeg.path,
              selectedFormatId: job.selectedFormatId,
              downloadSection: section,
              outputTemplate: outputTemplate,
              authentication: attemptAuthentication,
            );
        _activeDownloads[job.id] = session;
        _syncActiveState();

        final completer = Completer<void>();
        late final StreamSubscription<DownloadEvent> subscription;
        subscription = session.events.listen((event) async {
          switch (event) {
            case DownloadProgressEvent(:final progress):
              if (!_activeDownloads.containsKey(job.id)) return;
              final childProgress = (progress.percent ?? 4) / 100;
              _updateChild(
                job.id,
                child.id,
                (current) => current.copyWith(
                  status: DownloadStatus.downloading,
                  progress: childProgress.clamp(0.04, 0.98).toDouble(),
                  outputPath: destination,
                ),
              );
              _updateJobProgress(
                job.id,
                progress: _childProgressValue(
                  completedCount: completedCount,
                  currentChildProgress: childProgress,
                  totalCount: children.length,
                ),
                label:
                    'Downloading ${completedCount + 1} of ${children.length}',
              );
            case DownloadOutputEvent(:final path):
              downloadedFilePath = path;
              _updateChild(
                job.id,
                child.id,
                (current) => current.copyWith(
                  outputPath: destination,
                  downloadedFilePath: path,
                ),
              );
            case DownloadCompleteEvent():
              completedCount += 1;
              final completedAt = DateTime.now();
              final fileSize = await _fileSize(downloadedFilePath);
              _updateChild(
                job.id,
                child.id,
                (current) => current.copyWith(
                  status: DownloadStatus.complete,
                  progress: 1,
                  outputPath: destination,
                  downloadedFilePath: downloadedFilePath,
                  downloadedFileSize: fileSize,
                  completedAt: completedAt,
                ),
              );
              _updateJobProgress(
                job.id,
                progress: _itemProgressValue(
                  completedItems: completedCount,
                  totalItems: children.length,
                ),
                label: '$completedCount of ${children.length} downloaded',
              );
              completer.complete();
            case DownloadErrorEvent(:final message):
              if (_cancelledJobIds.contains(job.id)) {
                completer.completeError(const _DownloadStoppedException());
                return;
              }
              _updateChild(
                job.id,
                child.id,
                (current) => current.copyWith(
                  status: DownloadStatus.failed,
                  progress: 0,
                  error: message,
                  completedAt: DateTime.now(),
                ),
              );
              completer.completeError(YtDlpException(message));
          }
        });

        await completer.future.whenComplete(subscription.cancel);
      }

      _activeDownloads.remove(job.id);
      _syncActiveState();
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
            .appendLog('Selected child download complete.'),
      );
      reportStatus('Selected downloads complete: ${job.title}.');
      unawaited(_drainPendingDownloads());
    } on YtDlpException catch (error) {
      _activeDownloads.remove(job.id);
      _syncActiveState();
      if (_shouldRetryWithBrowserCookies(
        message: error.message,
        configuredAuthentication: authentication,
        attemptAuthentication: attemptAuthentication,
      )) {
        await _retryWithBrowserCookies(
          jobId: job.id,
          toolSet: toolSet,
          outputDirectory: baseDestination,
          authentication: authentication,
          reportStatus: reportStatus,
          cannotUseYtDlpMessage: cannotUseYtDlpMessage,
        );
        return;
      }
      _updateJob(
        job.id,
        (current) => current
            .copyWith(
              status: DownloadStatus.failed,
              eta: 'Failed',
              error: error.message,
              outputPath: destination,
              completedAt: DateTime.now(),
              children: _resetInterruptedChildren(current.children),
            )
            .appendLog('Selected child download failed: ${error.message}'),
      );
      reportStatus(error.message);
      unawaited(_drainPendingDownloads());
    } on _DownloadStoppedException {
      _activeDownloads.remove(job.id);
      _syncActiveState();
      _cancelledJobIds.remove(job.id);
      _updateJob(
        job.id,
        (current) => current
            .copyWith(
              status: DownloadStatus.stopped,
              eta: 'Stopped',
              error: null,
              outputPath: destination,
              completedAt: DateTime.now(),
              children: _resetInterruptedChildren(current.children),
            )
            .appendLog('Selected child download stopped by user.'),
      );
      reportStatus('Stopped download: ${job.title}.');
      unawaited(_drainPendingDownloads());
    } catch (error) {
      _activeDownloads.remove(job.id);
      _syncActiveState();
      _updateJob(
        job.id,
        (current) => current
            .copyWith(
              status: DownloadStatus.failed,
              eta: 'Failed',
              error: error.toString(),
              outputPath: destination,
              completedAt: DateTime.now(),
              children: _resetInterruptedChildren(current.children),
            )
            .appendLog('Selected child download failed: $error'),
      );
      reportStatus('Unexpected selected child download error: $error');
      unawaited(_drainPendingDownloads());
    }
  }

  void cancelAll() {
    _cancelAllSilently();
    _syncActiveState();
  }

  void _cancelAllSilently() {
    for (final session in _activeDownloads.values) {
      session.cancel();
    }
    _activeDownloads.clear();
    _pendingDownloads.clear();
    _cancelledJobIds.clear();
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
    DownloadItem Function(DownloadItem current) update,
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

  void _syncActiveState() {
    state = DownloadControllerState(
      activeJobIds: Set.unmodifiable(_activeDownloads.keys),
    );
  }

  bool _canQueue(DownloadJob job) {
    return job.status == DownloadStatus.ready ||
        job.status == DownloadStatus.stopped ||
        job.status == DownloadStatus.failed;
  }

  List<DownloadItem> _selectedDownloadableChildren(DownloadJob job) {
    return job.children
        .where(
          (child) =>
              child.isSelected &&
              (child.kind == DownloadItemKind.playlistEntry ||
                  child.kind == DownloadItemKind.chapter),
        )
        .toList(growable: false);
  }

  List<DownloadItem> _resetInterruptedChildren(List<DownloadItem> children) {
    return [
      for (final child in children)
        child.status == DownloadStatus.queued ||
                child.status == DownloadStatus.downloading
            ? child.copyWith(
                status: DownloadStatus.ready,
                progress: 0,
                clearStartedAt: true,
                clearCompletedAt: true,
              )
            : child,
    ];
  }

  Future<void> _drainPendingDownloads() async {
    final limit = _concurrencyLimit.maxConcurrent;
    while (_pendingDownloads.isNotEmpty &&
        (limit == null || _activeDownloads.length < limit)) {
      final request = _pendingDownloads.removeAt(0);
      if (_activeDownloads.containsKey(request.job.id)) continue;
      await start(
        job: request.job,
        toolSet: request.toolSet,
        outputDirectory: request.outputDirectory,
        authentication: request.authentication,
        reportStatus: request.reportStatus,
        cannotUseYtDlpMessage: request.cannotUseYtDlpMessage,
      );
    }
  }

  bool _shouldRetryWithBrowserCookies({
    required String message,
    required YtDlpAuthentication configuredAuthentication,
    required YtDlpAuthentication attemptAuthentication,
  }) {
    return configuredAuthentication.useBrowserCookies &&
        !attemptAuthentication.useBrowserCookies &&
        YtDlpErrorCleaner.looksAuthenticationRequired(message);
  }

  Future<void> _retryWithBrowserCookies({
    required String jobId,
    required ToolSet toolSet,
    required String outputDirectory,
    required YtDlpAuthentication authentication,
    required DownloadStatusReporter reportStatus,
    required String Function() cannotUseYtDlpMessage,
  }) async {
    _updateJob(
      jobId,
      (current) => current.appendLog(
        'Download requires authentication. Retrying with browser cookies.',
      ),
    );
    reportStatus('Retrying download with browser cookies...');

    final currentJob = ref
        .read(queueControllerProvider)
        .jobs
        .firstWhere((job) => job.id == jobId);
    await start(
      job: currentJob,
      toolSet: toolSet,
      outputDirectory: outputDirectory,
      authentication: authentication,
      reportStatus: reportStatus,
      cannotUseYtDlpMessage: cannotUseYtDlpMessage,
      useBrowserCookiesForAttempt: true,
    );
  }

  Future<int?> _fileSize(String? path) async {
    if (path == null) return null;
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      return file.length();
    } on FileSystemException {
      return null;
    }
  }

  double _nextProgressValue({
    required double current,
    required double? percent,
    required int completedItems,
    required int? totalItems,
  }) {
    if (percent != null) {
      final exact = (percent / 100).clamp(0.04, 0.98).toDouble();
      return exact < current ? current : exact;
    }

    final itemProgress = _itemProgressValue(
      completedItems: completedItems,
      totalItems: totalItems,
    );
    if (itemProgress > current) return itemProgress;

    return (current + 0.025).clamp(0.04, 0.92).toDouble();
  }

  double _itemProgressValue({
    required int completedItems,
    required int? totalItems,
  }) {
    if (totalItems == null || totalItems <= 0) return 0.04;
    return (completedItems / totalItems).clamp(0.04, 0.98).toDouble();
  }

  double _childProgressValue({
    required int completedCount,
    required double currentChildProgress,
    required int totalCount,
  }) {
    if (totalCount <= 0) return 0;
    final progress =
        (completedCount + currentChildProgress.clamp(0, 1)) / totalCount;
    return progress.clamp(0.04, 0.98).toDouble();
  }

  String? _downloadSectionFor(DownloadItem child) {
    final start = child.startTime;
    final end = child.endTime;
    if (child.kind != DownloadItemKind.chapter ||
        start == null ||
        end == null) {
      return null;
    }
    return '*${_seconds(start)}-${_seconds(end)}';
  }

  String _seconds(Duration duration) {
    return (duration.inMilliseconds / 1000).toStringAsFixed(3);
  }

  String _jobOutputDirectory(String baseDirectory, DownloadJob job) {
    final folderName = _safeFolderName(job.title);
    final separator = Platform.pathSeparator;
    final normalizedBase = baseDirectory.endsWith(separator)
        ? baseDirectory.substring(0, baseDirectory.length - 1)
        : baseDirectory;
    return '$normalizedBase$separator$folderName';
  }

  String _safeFolderName(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final fallback = sanitized.isEmpty ? 'Download' : sanitized;
    return fallback.length <= 80 ? fallback : fallback.substring(0, 80).trim();
  }
}

class _DownloadRequest {
  const _DownloadRequest({
    required this.job,
    required this.toolSet,
    required this.outputDirectory,
    required this.authentication,
    required this.reportStatus,
    required this.cannotUseYtDlpMessage,
  });

  final DownloadJob job;
  final ToolSet toolSet;
  final String? outputDirectory;
  final YtDlpAuthentication authentication;
  final DownloadStatusReporter reportStatus;
  final String Function() cannotUseYtDlpMessage;
}

class _DownloadStoppedException implements Exception {
  const _DownloadStoppedException();
}
