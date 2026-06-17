import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/download_models.dart';
import '../../../services/tools/tool_discovery.dart';
import '../../../services/yt_dlp/yt_dlp_authentication.dart';
import '../../../services/yt_dlp/yt_dlp_metadata_service.dart';
import '../../../services/yt_dlp/yt_dlp_service.dart';
import 'queue_controller.dart';

final ytDlpMetadataServiceProvider =
    Provider.family<YtDlpMetadataService, String>(
      (ref, executable) => YtDlpService(executable: executable),
    );

final analysisControllerProvider =
    NotifierProvider<AnalysisController, AnalysisControllerState>(
      AnalysisController.new,
    );

typedef AnalysisStatusReporter = void Function(String message);

class AnalysisControllerState {
  const AnalysisControllerState({this.isAnalyzing = false});

  final bool isAnalyzing;
}

class AnalysisController extends Notifier<AnalysisControllerState> {
  @override
  AnalysisControllerState build() => const AnalysisControllerState();

  Future<bool> analyze({
    required String url,
    required PresetDefinition preset,
    required ToolSet toolSet,
    required YtDlpAuthentication authentication,
    required AnalysisStatusReporter reportStatus,
    required String Function() cannotUseYtDlpMessage,
  }) async {
    final rawUrl = url.trim();
    if (rawUrl.isEmpty) {
      reportStatus(
        'Paste a URL into the field, or copy one and press Add again.',
      );
      return false;
    }

    if (state.isAnalyzing) {
      reportStatus('Already analyzing a URL. Please wait.');
      return false;
    }

    final executable = toolSet.ytDlp.path;
    if (!toolSet.ytDlp.isAvailable || executable == null) {
      reportStatus(cannotUseYtDlpMessage());
      return false;
    }

    final existingJob = ref.read(queueControllerProvider).jobByUrl(rawUrl);
    if (existingJob != null) {
      ref.read(queueControllerProvider.notifier).selectJob(existingJob.id);
      reportStatus('This URL is already in the queue: ${existingJob.title}.');
      return false;
    }

    reportStatus('Add received. Preparing metadata analysis...');

    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final pendingJob = DownloadJob(
      id: id,
      url: rawUrl,
      title: 'Analyzing URL',
      source: rawUrl,
      preset: preset,
      status: DownloadStatus.analyzing,
      progress: 0.08,
      eta: 'Reading metadata',
      logLines: const ['Metadata analysis started.'],
    );

    state = const AnalysisControllerState(isAnalyzing: true);
    reportStatus('Running yt-dlp metadata analysis...');
    ref.read(queueControllerProvider.notifier).insertFirst(pendingJob);

    try {
      final mediaInfo = await _getMetadataWithCookieFallback(
        executable: executable,
        url: rawUrl,
        authentication: authentication,
        reportStatus: reportStatus,
      );
      _replaceJob(
        id,
        pendingJob.copyWith(
          title: mediaInfo.title,
          source: mediaInfo.sourceLabel,
          status: DownloadStatus.ready,
          progress: 0,
          eta: mediaInfo.isPlaylist
              ? '${mediaInfo.playlistCount} items'
              : mediaInfo.durationLabel,
          mediaInfo: mediaInfo,
          children: _downloadItemsFor(mediaInfo),
          isExpanded: mediaInfo.entries.isNotEmpty || mediaInfo.hasChapters,
          logLines: [
            ...pendingJob.logLines,
            mediaInfo.isPlaylist
                ? 'Analyzed playlist with ${mediaInfo.playlistCount} items.'
                : 'Analyzed video metadata.',
          ],
        ),
      );
      reportStatus(
        mediaInfo.isPlaylist
            ? 'Analyzed playlist: ${mediaInfo.title}.'
            : 'Analyzed video: ${mediaInfo.title}.',
      );
      return true;
    } on YtDlpException catch (error) {
      _replaceJob(
        id,
        pendingJob.copyWith(
          title: 'Analysis failed',
          status: DownloadStatus.failed,
          progress: 0,
          eta: 'Failed',
          error: error.message,
          logLines: [
            ...pendingJob.logLines,
            'Analysis failed: ${error.message}',
          ],
        ),
      );
      reportStatus(error.message);
      return false;
    } catch (error) {
      _replaceJob(
        id,
        pendingJob.copyWith(
          title: 'Analysis failed',
          status: DownloadStatus.failed,
          progress: 0,
          eta: 'Failed',
          error: error.toString(),
          logLines: [...pendingJob.logLines, 'Analysis failed: $error'],
        ),
      );
      reportStatus('Unexpected analysis error: $error');
      return false;
    } finally {
      state = const AnalysisControllerState();
    }
  }

  Future<bool> retry({
    required DownloadJob job,
    required ToolSet toolSet,
    required YtDlpAuthentication authentication,
    required AnalysisStatusReporter reportStatus,
    required String Function() cannotUseYtDlpMessage,
  }) async {
    if (state.isAnalyzing) {
      reportStatus('Already analyzing a URL. Please wait.');
      return false;
    }

    final executable = toolSet.ytDlp.path;
    if (!toolSet.ytDlp.isAvailable || executable == null) {
      reportStatus(cannotUseYtDlpMessage());
      return false;
    }

    final retryJob = job.copyWith(
      title: job.title == 'Analysis failed' ? 'Analyzing URL' : job.title,
      status: DownloadStatus.analyzing,
      progress: 0.08,
      eta: 'Reading metadata',
      error: null,
      clearSelectedFormat: true,
      clearDownloadedFilePath: true,
      clearDownloadedFileSize: true,
      clearStartedAt: true,
      clearCompletedAt: true,
      logLines: [...job.logLines, 'Analysis retry started.'],
    );

    state = const AnalysisControllerState(isAnalyzing: true);
    _replaceJob(job.id, retryJob);
    reportStatus('Retrying metadata analysis...');

    try {
      final mediaInfo = await _getMetadataWithCookieFallback(
        executable: executable,
        url: job.url,
        authentication: authentication,
        reportStatus: reportStatus,
      );
      _replaceJob(
        job.id,
        retryJob.copyWith(
          title: mediaInfo.title,
          source: mediaInfo.sourceLabel,
          status: DownloadStatus.ready,
          progress: 0,
          eta: mediaInfo.isPlaylist
              ? '${mediaInfo.playlistCount} items'
              : mediaInfo.durationLabel,
          mediaInfo: mediaInfo,
          children: _downloadItemsFor(mediaInfo),
          isExpanded: mediaInfo.entries.isNotEmpty || mediaInfo.hasChapters,
          error: null,
          logLines: [
            ...retryJob.logLines,
            mediaInfo.isPlaylist
                ? 'Analyzed playlist with ${mediaInfo.playlistCount} items.'
                : 'Analyzed video metadata.',
          ],
        ),
      );
      reportStatus(
        mediaInfo.isPlaylist
            ? 'Analyzed playlist: ${mediaInfo.title}.'
            : 'Analyzed video: ${mediaInfo.title}.',
      );
      return true;
    } on YtDlpException catch (error) {
      _replaceJob(
        job.id,
        retryJob.copyWith(
          title: 'Analysis failed',
          status: DownloadStatus.failed,
          progress: 0,
          eta: 'Failed',
          error: error.message,
          logLines: [...retryJob.logLines, 'Analysis failed: ${error.message}'],
        ),
      );
      reportStatus(error.message);
      return false;
    } catch (error) {
      _replaceJob(
        job.id,
        retryJob.copyWith(
          title: 'Analysis failed',
          status: DownloadStatus.failed,
          progress: 0,
          eta: 'Failed',
          error: error.toString(),
          logLines: [...retryJob.logLines, 'Analysis failed: $error'],
        ),
      );
      reportStatus('Unexpected analysis error: $error');
      return false;
    } finally {
      state = const AnalysisControllerState();
    }
  }

  void _replaceJob(String id, DownloadJob replacement) {
    ref.read(queueControllerProvider.notifier).replace(id, replacement);
  }

  List<DownloadItem> _downloadItemsFor(MediaInfo mediaInfo) {
    if (mediaInfo.entries.isNotEmpty) {
      return mediaInfo.entries
          .map((entry) {
            final index = entry.playlistIndex;
            return DownloadItem(
              id: 'entry:${entry.id}',
              kind: DownloadItemKind.playlistEntry,
              title: index == null ? entry.title : '$index. ${entry.title}',
              url: entry.webpageUrl,
              source: entry.extractor ?? mediaInfo.sourceLabel,
              thumbnail: entry.thumbnail,
              duration: entry.duration,
              status: DownloadStatus.ready,
              progress: 0,
            );
          })
          .toList(growable: false);
    }

    if (mediaInfo.chapters.isNotEmpty) {
      return mediaInfo.chapters.indexed
          .map((item) {
            final (index, chapter) = item;
            return DownloadItem(
              id: 'chapter:${index + 1}',
              kind: DownloadItemKind.chapter,
              title: chapter.title,
              url: mediaInfo.webpageUrl,
              source: mediaInfo.sourceLabel,
              thumbnail: mediaInfo.thumbnail,
              duration: chapter.duration,
              startTime: chapter.startTime,
              endTime: chapter.endTime,
              status: DownloadStatus.ready,
              progress: 0,
            );
          })
          .toList(growable: false);
    }

    return const [];
  }

  Future<MediaInfo> _getMetadataWithCookieFallback({
    required String executable,
    required String url,
    required YtDlpAuthentication authentication,
    required AnalysisStatusReporter reportStatus,
  }) async {
    final service = ref.read(ytDlpMetadataServiceProvider(executable));
    try {
      return await service.getMetadata(url);
    } on YtDlpException catch (error) {
      if (!authentication.useBrowserCookies ||
          !YtDlpErrorCleaner.looksAuthenticationRequired(error.message)) {
        rethrow;
      }
      reportStatus('Retrying metadata analysis with browser cookies...');
      return service.getMetadata(url, authentication: authentication);
    }
  }
}
