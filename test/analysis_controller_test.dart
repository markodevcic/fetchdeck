import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/features/downloads/application/analysis_controller.dart';
import 'package:yt_dlp_desktop/features/downloads/application/queue_controller.dart';
import 'package:yt_dlp_desktop/models/download_models.dart';
import 'package:yt_dlp_desktop/services/queue/queue_repository.dart';
import 'package:yt_dlp_desktop/services/tools/tool_discovery.dart';
import 'package:yt_dlp_desktop/services/yt_dlp/yt_dlp_authentication.dart';
import 'package:yt_dlp_desktop/services/yt_dlp/yt_dlp_metadata_service.dart';

void main() {
  test('analyze inserts ready job with parsed metadata', () async {
    final container = _container(
      metadataService: _FakeMetadataService(
        mediaInfo: const MediaInfo(
          title: 'Example Video',
          webpageUrl: 'https://example.com/video',
          extractor: 'Example',
          formatCount: 3,
          duration: Duration(seconds: 90),
        ),
      ),
    );
    addTearDown(container.dispose);

    String? statusMessage;
    final didAnalyze = await container
        .read(analysisControllerProvider.notifier)
        .analyze(
          url: 'https://example.com/video',
          preset: PresetDefinition.defaultPreset,
          toolSet: _toolSet(),
          authentication: YtDlpAuthentication.none,
          reportStatus: (message) => statusMessage = message,
          cannotUseYtDlpMessage: () => 'yt-dlp unavailable',
        );

    final job = container.read(queueControllerProvider).jobs.single;
    expect(didAnalyze, isTrue);
    expect(statusMessage, 'Analyzed video: Example Video.');
    expect(job.title, 'Example Video');
    expect(job.status, DownloadStatus.ready);
    expect(job.mediaInfo?.duration, const Duration(seconds: 90));
  });

  test('analyze selects duplicate job without adding another item', () async {
    final container = _container(metadataService: _FakeMetadataService());
    addTearDown(container.dispose);

    final existing = _job('existing');
    container.read(queueControllerProvider.notifier).insertFirst(existing);

    String? statusMessage;
    final didAnalyze = await container
        .read(analysisControllerProvider.notifier)
        .analyze(
          url: 'https://example.com/existing/#comments',
          preset: PresetDefinition.defaultPreset,
          toolSet: _toolSet(),
          authentication: YtDlpAuthentication.none,
          reportStatus: (message) => statusMessage = message,
          cannotUseYtDlpMessage: () => 'yt-dlp unavailable',
        );

    final state = container.read(queueControllerProvider);
    expect(didAnalyze, isFalse);
    expect(statusMessage, 'This URL is already in the queue: existing.');
    expect(state.jobs, hasLength(1));
    expect(state.selectedJobId, existing.id);
  });

  test('analyze attaches playlist entries as selected child items', () async {
    final container = _container(
      metadataService: _FakeMetadataService(
        mediaInfo: const MediaInfo(
          title: 'Example Playlist',
          webpageUrl: 'https://example.com/playlist',
          extractor: 'Example',
          formatCount: 0,
          playlistTitle: 'Example Playlist',
          playlistCount: 2,
          entries: [
            MediaEntry(
              id: 'one',
              title: 'First Track',
              webpageUrl: 'https://example.com/watch/one',
              extractor: 'Example',
              duration: Duration(seconds: 120),
              playlistIndex: 1,
            ),
            MediaEntry(
              id: 'two',
              title: 'Second Track',
              webpageUrl: 'https://example.com/watch/two',
              extractor: 'Example',
              duration: Duration(seconds: 150),
              playlistIndex: 2,
            ),
          ],
        ),
      ),
    );
    addTearDown(container.dispose);

    final didAnalyze = await container
        .read(analysisControllerProvider.notifier)
        .analyze(
          url: 'https://example.com/playlist',
          preset: PresetDefinition.defaultPreset,
          toolSet: _toolSet(),
          authentication: YtDlpAuthentication.none,
          reportStatus: (_) {},
          cannotUseYtDlpMessage: () => 'yt-dlp unavailable',
        );

    final job = container.read(queueControllerProvider).jobs.single;
    expect(didAnalyze, isTrue);
    expect(job.isExpanded, isTrue);
    expect(job.children, hasLength(2));
    expect(job.selectedChildCount, 2);
    expect(job.children.first.kind, DownloadItemKind.playlistEntry);
    expect(job.children.first.title, '1. First Track');
    expect(job.children.first.url, 'https://example.com/watch/one');
  });

  test(
    'retry refreshes failed analysis job before metadata completes',
    () async {
      final metadataService = _PendingMetadataService();
      final container = _container(metadataService: metadataService);
      addTearDown(container.dispose);

      final failedJob = _job('failed-analysis').copyWith(
        title: 'Analysis failed',
        status: DownloadStatus.failed,
        progress: 0,
        eta: 'Failed',
        error: 'Previous analysis failure',
        logLines: const ['Analysis failed: Previous analysis failure'],
      );
      container.read(queueControllerProvider.notifier).insertFirst(failedJob);

      final retryFuture = container
          .read(analysisControllerProvider.notifier)
          .retry(
            job: failedJob,
            toolSet: _toolSet(),
            authentication: YtDlpAuthentication.none,
            reportStatus: (_) {},
            cannotUseYtDlpMessage: () => 'yt-dlp unavailable',
          );

      final refreshingJob = container.read(queueControllerProvider).jobs.single;
      expect(refreshingJob.status, DownloadStatus.analyzing);
      expect(refreshingJob.error, isNull);
      expect(refreshingJob.eta, 'Reading metadata');
      expect(refreshingJob.logLines, contains('Analysis retry started.'));

      metadataService.complete(
        const MediaInfo(
          title: 'Retried Video',
          webpageUrl: 'https://example.com/failed-analysis',
          extractor: 'Example',
          formatCount: 1,
        ),
      );
      await retryFuture;

      final readyJob = container.read(queueControllerProvider).jobs.single;
      expect(readyJob.status, DownloadStatus.ready);
      expect(readyJob.title, 'Retried Video');
    },
  );
}

ProviderContainer _container({required YtDlpMetadataService metadataService}) {
  return ProviderContainer(
    overrides: [
      queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
      ytDlpMetadataServiceProvider.overrideWith(
        (ref, executable) => metadataService,
      ),
    ],
  );
}

class _MemoryQueueRepository extends QueueRepository {
  final savedJobs = <DownloadJob>[];

  @override
  Future<List<DownloadJob>> load() async => savedJobs;

  @override
  Future<void> save(List<DownloadJob> jobs) async {
    savedJobs
      ..clear()
      ..addAll(jobs);
  }
}

class _FakeMetadataService implements YtDlpMetadataService {
  const _FakeMetadataService({this.mediaInfo});

  final MediaInfo? mediaInfo;

  @override
  Future<MediaInfo> getMetadata(
    String url, {
    YtDlpAuthentication authentication = YtDlpAuthentication.none,
  }) async {
    return mediaInfo ??
        MediaInfo(
          title: url,
          webpageUrl: url,
          extractor: 'Example',
          formatCount: 1,
        );
  }
}

class _PendingMetadataService implements YtDlpMetadataService {
  final _completer = Completer<MediaInfo>();

  @override
  Future<MediaInfo> getMetadata(
    String url, {
    YtDlpAuthentication authentication = YtDlpAuthentication.none,
  }) => _completer.future;

  void complete(MediaInfo mediaInfo) {
    _completer.complete(mediaInfo);
  }
}

ToolSet _toolSet() {
  return const ToolSet(
    ytDlp: ToolInfo.available(path: '/tmp/yt-dlp', version: 'test'),
    ffmpeg: ToolInfo.missing(),
    ffprobe: ToolInfo.missing(),
  );
}

DownloadJob _job(String id) {
  return DownloadJob(
    id: id,
    url: 'https://example.com/$id',
    title: id,
    source: 'example.com',
    preset: PresetDefinition.defaultPreset,
    status: DownloadStatus.ready,
    progress: 0,
    eta: DownloadStatus.ready.label,
  );
}
