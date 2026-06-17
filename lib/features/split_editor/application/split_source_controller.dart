import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/download_models.dart';
import '../../../services/tools/tool_discovery.dart';
import '../../../services/yt_dlp/yt_dlp_authentication.dart';
import '../../../services/yt_dlp/yt_dlp_service.dart';
import '../../downloads/application/download_controller.dart';
import '../../downloads/application/queue_controller.dart';

final splitSourceControllerProvider =
    NotifierProvider<SplitSourceController, SplitSourceState>(
      SplitSourceController.new,
    );

final splitSourceYtDlpServiceProvider = Provider.family<YtDlpService, String>(
  (ref, executable) => YtDlpService(executable: executable),
);

class SplitSourceState {
  const SplitSourceState({this.activeJobIds = const {}});

  final Set<String> activeJobIds;

  bool isActive(String jobId) => activeJobIds.contains(jobId);
}

class SplitSourceController extends Notifier<SplitSourceState> {
  final _activeSessions = <String, YtDlpDownloadSession>{};

  @override
  SplitSourceState build() {
    ref.onDispose(_cancelAllSilently);
    return const SplitSourceState();
  }

  Future<DownloadJob?> prepare({
    required DownloadJob job,
    required ToolSet toolSet,
    required String? outputDirectory,
    required YtDlpAuthentication authentication,
    required DownloadStatusReporter reportStatus,
    required String Function() cannotUseYtDlpMessage,
  }) async {
    final existingSource = job.splitEditorSourcePath;
    if (existingSource != null && await File(existingSource).exists()) {
      return job;
    }

    final executable = toolSet.ytDlp.path;
    if (!toolSet.ytDlp.isAvailable || executable == null) {
      reportStatus(cannotUseYtDlpMessage());
      return null;
    }
    if (outputDirectory == null) {
      reportStatus('Choose an output folder before preparing split source.');
      return null;
    }
    if (job.mediaInfo == null) {
      reportStatus('Analyze the URL before preparing split source.');
      return null;
    }
    if (_activeSessions.containsKey(job.id)) {
      reportStatus('Split source is already being prepared for ${job.title}.');
      return null;
    }

    final sourceDirectory = _splitSourceDirectory(outputDirectory, job);
    reportStatus('Preparing split source for ${job.title}...');
    _updateJob(
      job.id,
      (current) =>
          current.appendLog('Preparing split source in $sourceDirectory.'),
    );

    try {
      await Directory(sourceDirectory).create(recursive: true);
      String? sourceFilePath;
      final session = await ref
          .read(splitSourceYtDlpServiceProvider(executable))
          .startDownload(
            url: job.url,
            preset: job.preset,
            outputDirectory: sourceDirectory,
            isPlaylist: false,
            ffmpegPath: toolSet.ffmpeg.path,
            selectedFormatId: job.selectedFormatId,
            authentication: authentication,
          );

      _activeSessions[job.id] = session;
      _syncActiveState();

      final completer = Completer<DownloadJob?>();
      late final StreamSubscription<DownloadEvent> subscription;
      subscription = session.events.listen((event) {
        switch (event) {
          case DownloadProgressEvent(:final progress):
            reportStatus('${job.title}: preparing source ${progress.label}');
          case DownloadOutputEvent(:final path):
            sourceFilePath = path;
          case DownloadCompleteEvent():
            _activeSessions.remove(job.id);
            _syncActiveState();
            final preparedPath = sourceFilePath;
            if (preparedPath == null) {
              const message =
                  'yt-dlp finished but did not report a source file.';
              _updateJob(
                job.id,
                (current) => current.appendLog(
                  'Split source preparation failed: $message',
                ),
              );
              reportStatus(message);
              completer.complete(null);
              break;
            }

            _updateJob(
              job.id,
              (current) => current
                  .copyWith(splitSourceFilePath: preparedPath)
                  .appendLog('Split source prepared: $preparedPath'),
            );
            final preparedJob = _jobById(job.id);
            reportStatus('Split source ready for ${preparedJob.title}.');
            completer.complete(preparedJob);
          case DownloadErrorEvent(:final message):
            _activeSessions.remove(job.id);
            _syncActiveState();
            _updateJob(
              job.id,
              (current) => current.appendLog(
                'Split source preparation failed: $message',
              ),
            );
            reportStatus(message);
            completer.complete(null);
        }
      });

      return await completer.future.whenComplete(subscription.cancel);
    } on YtDlpException catch (error) {
      _activeSessions.remove(job.id);
      _syncActiveState();
      _updateJob(
        job.id,
        (current) => current.appendLog(
          'Split source preparation failed: ${error.message}',
        ),
      );
      reportStatus(error.message);
      return null;
    } catch (error) {
      _activeSessions.remove(job.id);
      _syncActiveState();
      _updateJob(
        job.id,
        (current) =>
            current.appendLog('Split source preparation failed: $error'),
      );
      reportStatus('Unexpected split source error: $error');
      return null;
    }
  }

  void cancel(DownloadJob job) {
    final session = _activeSessions.remove(job.id);
    session?.cancel();
    _syncActiveState();
  }

  void _cancelAllSilently() {
    for (final session in _activeSessions.values) {
      session.cancel();
    }
    _activeSessions.clear();
  }

  void _updateJob(String id, DownloadJob Function(DownloadJob current) update) {
    ref.read(queueControllerProvider.notifier).update(id, update);
  }

  DownloadJob _jobById(String id) {
    return ref
        .read(queueControllerProvider)
        .jobs
        .firstWhere((job) => job.id == id);
  }

  void _syncActiveState() {
    state = SplitSourceState(
      activeJobIds: Set.unmodifiable(_activeSessions.keys),
    );
  }

  String _splitSourceDirectory(String baseDirectory, DownloadJob job) {
    final separator = Platform.pathSeparator;
    final normalizedBase = baseDirectory.endsWith(separator)
        ? baseDirectory.substring(0, baseDirectory.length - 1)
        : baseDirectory;
    return [
      normalizedBase,
      _safeFolderName(job.title),
      '.fetchdeck',
      'source',
    ].join(separator);
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
