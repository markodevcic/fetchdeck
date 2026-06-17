import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/features/downloads/application/download_controller.dart';
import 'package:yt_dlp_desktop/features/downloads/application/queue_controller.dart';
import 'package:yt_dlp_desktop/features/settings/application/download_concurrency_limit.dart';
import 'package:yt_dlp_desktop/models/download_models.dart';
import 'package:yt_dlp_desktop/services/queue/queue_repository.dart';
import 'package:yt_dlp_desktop/services/tools/tool_discovery.dart';
import 'package:yt_dlp_desktop/services/yt_dlp/yt_dlp_authentication.dart';
import 'package:yt_dlp_desktop/services/yt_dlp/yt_dlp_service.dart';

void main() {
  test('start reports missing yt-dlp without mutating the job', () async {
    final container = ProviderContainer(
      overrides: [
        queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
      ],
    );
    addTearDown(container.dispose);

    final job = _job('job-1');
    container.read(queueControllerProvider.notifier).insertFirst(job);

    String? statusMessage;
    await container
        .read(downloadControllerProvider.notifier)
        .start(
          job: job,
          toolSet: const ToolSet.empty(),
          outputDirectory: '/tmp/Fetchdeck',
          authentication: YtDlpAuthentication.none,
          reportStatus: (message) => statusMessage = message,
          cannotUseYtDlpMessage: () => 'yt-dlp unavailable',
        );

    final restored = container.read(queueControllerProvider).jobs.single;
    expect(statusMessage, 'yt-dlp unavailable');
    expect(restored.status, DownloadStatus.ready);
    expect(restored.progress, 0);
    expect(restored.logLines, isEmpty);
  });

  test(
    'retrying failed job appends retry log before process failure',
    () async {
      final container = ProviderContainer(
        overrides: [
          queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
        ],
      );
      addTearDown(container.dispose);

      final outputDirectory = await Directory.systemTemp.createTemp(
        'fetchdeck-test-',
      );
      addTearDown(() => outputDirectory.delete(recursive: true));

      final job = _job('job-1').copyWith(
        status: DownloadStatus.failed,
        eta: 'Failed',
        error: 'Previous failure',
        logLines: const ['Download failed: Previous failure'],
      );
      container.read(queueControllerProvider.notifier).insertFirst(job);

      await container
          .read(downloadControllerProvider.notifier)
          .start(
            job: job,
            toolSet: const ToolSet(
              ytDlp: ToolInfo.available(
                path: '/definitely/missing/yt-dlp',
                version: 'test',
              ),
              ffmpeg: ToolInfo.missing(),
              ffprobe: ToolInfo.missing(),
            ),
            outputDirectory: outputDirectory.path,
            authentication: YtDlpAuthentication.none,
            reportStatus: (_) {},
            cannotUseYtDlpMessage: () => 'yt-dlp unavailable',
          );

      final restored = container.read(queueControllerProvider).jobs.single;
      expect(restored.status, DownloadStatus.failed);
      expect(restored.logLines, contains('Retry started.'));
      expect(restored.logLines, contains('Download started.'));
      expect(
        restored.logLines.any((line) => line.startsWith('Download failed:')),
        isTrue,
      );
    },
  );

  test('retrying failed job refreshes status before process starts', () async {
    final outputDirectory = await Directory.systemTemp.createTemp(
      'fetchdeck-test-',
    );
    addTearDown(() => outputDirectory.delete(recursive: true));
    final fakeService = _PendingYtDlpService();
    final container = ProviderContainer(
      overrides: [
        queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
        ytDlpDownloadServiceProvider.overrideWith(
          (ref, executable) => fakeService,
        ),
      ],
    );
    addTearDown(container.dispose);

    final job = _job('job-1').copyWith(
      status: DownloadStatus.failed,
      eta: 'Failed',
      error: 'Previous failure',
      logLines: const ['Download failed: Previous failure'],
    );
    container.read(queueControllerProvider.notifier).insertFirst(job);

    final startFuture = container
        .read(downloadControllerProvider.notifier)
        .start(
          job: job,
          toolSet: const ToolSet(
            ytDlp: ToolInfo.available(path: '/tools/yt-dlp', version: 'test'),
            ffmpeg: ToolInfo.missing(),
            ffprobe: ToolInfo.missing(),
          ),
          outputDirectory: outputDirectory.path,
          authentication: YtDlpAuthentication.none,
          reportStatus: (_) {},
          cannotUseYtDlpMessage: () => 'yt-dlp unavailable',
        );

    final refreshingJob = container.read(queueControllerProvider).jobs.single;
    expect(refreshingJob.status, DownloadStatus.downloading);
    expect(refreshingJob.error, isNull);
    expect(refreshingJob.eta, 'Starting');
    expect(refreshingJob.logLines, contains('Retry started.'));

    fakeService.completeStart();
    await startFuture;
  });

  test('startAll respects the configured concurrency limit', () async {
    final fakeService = _FakeYtDlpService();
    final container = ProviderContainer(
      overrides: [
        queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
        ytDlpDownloadServiceProvider.overrideWith(
          (ref, executable) => fakeService,
        ),
      ],
    );
    addTearDown(container.dispose);

    final queue = container.read(queueControllerProvider.notifier);
    queue.insertFirst(_job('third'));
    queue.insertFirst(_job('second'));
    queue.insertFirst(_job('first'));

    await container
        .read(downloadControllerProvider.notifier)
        .startAll(
          jobs: container.read(queueControllerProvider).jobs,
          toolSet: const ToolSet(
            ytDlp: ToolInfo.available(path: '/tools/yt-dlp', version: 'test'),
            ffmpeg: ToolInfo.missing(),
            ffprobe: ToolInfo.missing(),
          ),
          outputDirectory: '/tmp/Fetchdeck',
          concurrencyLimit: DownloadConcurrencyLimit.two,
          authentication: YtDlpAuthentication.none,
          reportStatus: (_) {},
          cannotUseYtDlpMessage: () => 'yt-dlp unavailable',
        );

    expect(fakeService.sessions, hasLength(2));
    expect(
      container.read(downloadControllerProvider).activeJobIds,
      hasLength(2),
    );
    expect(
      container.read(queueControllerProvider).jobs.map((job) => job.status),
      [
        DownloadStatus.downloading,
        DownloadStatus.downloading,
        DownloadStatus.queued,
      ],
    );

    fakeService.sessions.first.complete();
    await _waitUntil(() => fakeService.sessions.length == 3);

    expect(fakeService.sessions, hasLength(3));
    expect(
      container.read(downloadControllerProvider).activeJobIds,
      hasLength(2),
    );
    expect(
      container.read(queueControllerProvider).jobs.map((job) => job.status),
      [
        DownloadStatus.complete,
        DownloadStatus.downloading,
        DownloadStatus.downloading,
      ],
    );
  });

  test('completed downloads keep the detected file size', () async {
    final outputDirectory = await Directory.systemTemp.createTemp(
      'fetchdeck-test-',
    );
    addTearDown(() => outputDirectory.delete(recursive: true));
    final outputFile = File('${outputDirectory.path}/example.mp3');
    await outputFile.writeAsBytes(List<int>.filled(1536, 1));

    final fakeService = _FakeYtDlpService();
    final container = ProviderContainer(
      overrides: [
        queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
        ytDlpDownloadServiceProvider.overrideWith(
          (ref, executable) => fakeService,
        ),
      ],
    );
    addTearDown(container.dispose);

    final job = _job('job-1');
    container.read(queueControllerProvider.notifier).insertFirst(job);

    await container
        .read(downloadControllerProvider.notifier)
        .start(
          job: job,
          toolSet: const ToolSet(
            ytDlp: ToolInfo.available(path: '/tools/yt-dlp', version: 'test'),
            ffmpeg: ToolInfo.missing(),
            ffprobe: ToolInfo.missing(),
          ),
          outputDirectory: outputDirectory.path,
          authentication: YtDlpAuthentication.none,
          reportStatus: (_) {},
          cannotUseYtDlpMessage: () => 'yt-dlp unavailable',
        );

    fakeService.sessions.single.output(outputFile.path);
    fakeService.sessions.single.complete();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    final restored = container.read(queueControllerProvider).jobs.single;
    expect(restored.status, DownloadStatus.complete);
    expect(restored.downloadedFilePath, outputFile.path);
    expect(restored.downloadedFileSize, 1536);
    expect(restored.completedAt, isNotNull);
  });

  test('downloads are written into a dedicated job folder', () async {
    final outputDirectory = await Directory.systemTemp.createTemp(
      'fetchdeck-test-',
    );
    addTearDown(() => outputDirectory.delete(recursive: true));

    final fakeService = _FakeYtDlpService();
    final container = ProviderContainer(
      overrides: [
        queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
        ytDlpDownloadServiceProvider.overrideWith(
          (ref, executable) => fakeService,
        ),
      ],
    );
    addTearDown(container.dispose);

    final job = _job('job-1').copyWith(title: 'Bible in Song');
    container.read(queueControllerProvider.notifier).insertFirst(job);

    await container
        .read(downloadControllerProvider.notifier)
        .start(
          job: job,
          toolSet: const ToolSet(
            ytDlp: ToolInfo.available(path: '/tools/yt-dlp', version: 'test'),
            ffmpeg: ToolInfo.missing(),
            ffprobe: ToolInfo.missing(),
          ),
          outputDirectory: outputDirectory.path,
          authentication: YtDlpAuthentication.none,
          reportStatus: (_) {},
          cannotUseYtDlpMessage: () => 'yt-dlp unavailable',
        );

    final jobOutputDirectory =
        '${outputDirectory.path}${Platform.pathSeparator}Bible in Song';
    expect(fakeService.outputDirectories.single, jobOutputDirectory);
    expect(
      container.read(queueControllerProvider).jobs.single.outputPath,
      jobOutputDirectory,
    );
  });

  test('download progress advances when yt-dlp omits percent', () async {
    final fakeService = _FakeYtDlpService();
    final container = ProviderContainer(
      overrides: [
        queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
        ytDlpDownloadServiceProvider.overrideWith(
          (ref, executable) => fakeService,
        ),
      ],
    );
    addTearDown(container.dispose);

    final job = _job('job-1');
    container.read(queueControllerProvider.notifier).insertFirst(job);

    await container
        .read(downloadControllerProvider.notifier)
        .start(
          job: job,
          toolSet: const ToolSet(
            ytDlp: ToolInfo.available(path: '/tools/yt-dlp', version: 'test'),
            ffmpeg: ToolInfo.missing(),
            ffprobe: ToolInfo.missing(),
          ),
          outputDirectory: '/tmp/Fetchdeck',
          authentication: YtDlpAuthentication.none,
          reportStatus: (_) {},
          cannotUseYtDlpMessage: () => 'yt-dlp unavailable',
        );

    final startingProgress = container
        .read(queueControllerProvider)
        .jobs
        .single
        .progress;
    fakeService.sessions.single.progress(
      const DownloadProgress(status: 'downloading'),
    );
    await Future<void>.delayed(Duration.zero);

    final restored = container.read(queueControllerProvider).jobs.single;
    expect(restored.progress, greaterThan(startingProgress));
  });

  test(
    'playlist output events advance progress by completed item count',
    () async {
      final fakeService = _FakeYtDlpService();
      final container = ProviderContainer(
        overrides: [
          queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
          ytDlpDownloadServiceProvider.overrideWith(
            (ref, executable) => fakeService,
          ),
        ],
      );
      addTearDown(container.dispose);

      final job = _job('playlist').copyWith(
        mediaInfo: const MediaInfo(
          title: 'Playlist',
          webpageUrl: 'https://example.com/playlist',
          extractor: 'Example',
          formatCount: 1,
          playlistTitle: 'Playlist',
          playlistCount: 4,
        ),
      );
      container.read(queueControllerProvider.notifier).insertFirst(job);

      await container
          .read(downloadControllerProvider.notifier)
          .start(
            job: job,
            toolSet: const ToolSet(
              ytDlp: ToolInfo.available(path: '/tools/yt-dlp', version: 'test'),
              ffmpeg: ToolInfo.missing(),
              ffprobe: ToolInfo.missing(),
            ),
            outputDirectory: '/tmp/Fetchdeck',
            authentication: YtDlpAuthentication.none,
            reportStatus: (_) {},
            cannotUseYtDlpMessage: () => 'yt-dlp unavailable',
          );

      fakeService.sessions.single.output('/tmp/Fetchdeck/Playlist/001.mp3');
      await Future<void>.delayed(Duration.zero);

      final restored = container.read(queueControllerProvider).jobs.single;
      expect(restored.progress, 0.25);
      expect(restored.eta, '1 of 4 files');
    },
  );

  test('downloads only selected playlist child entries', () async {
    final fakeService = _FakeYtDlpService();
    final container = ProviderContainer(
      overrides: [
        queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
        ytDlpDownloadServiceProvider.overrideWith(
          (ref, executable) => fakeService,
        ),
      ],
    );
    addTearDown(container.dispose);

    final job = _job('playlist').copyWith(
      children: const [
        DownloadItem(
          id: 'entry:one',
          kind: DownloadItemKind.playlistEntry,
          title: 'One',
          url: 'https://example.com/watch/one',
          status: DownloadStatus.ready,
          progress: 0,
        ),
        DownloadItem(
          id: 'entry:two',
          kind: DownloadItemKind.playlistEntry,
          title: 'Two',
          url: 'https://example.com/watch/two',
          status: DownloadStatus.ready,
          progress: 0,
          isSelected: false,
        ),
      ],
    );
    container.read(queueControllerProvider.notifier).insertFirst(job);

    final startFuture = container
        .read(downloadControllerProvider.notifier)
        .start(
          job: job,
          toolSet: const ToolSet(
            ytDlp: ToolInfo.available(path: '/tools/yt-dlp', version: 'test'),
            ffmpeg: ToolInfo.missing(),
            ffprobe: ToolInfo.missing(),
          ),
          outputDirectory: '/tmp/Fetchdeck',
          authentication: YtDlpAuthentication.none,
          reportStatus: (_) {},
          cannotUseYtDlpMessage: () => 'yt-dlp unavailable',
        );

    await _waitUntil(() => fakeService.sessions.length == 1);
    expect(fakeService.urls, ['https://example.com/watch/one']);
    expect(fakeService.downloadSections, [null]);
    fakeService.sessions.single.output('/tmp/Fetchdeck/playlist/One.mp3');
    fakeService.sessions.single.complete();
    await startFuture;

    final restored = container.read(queueControllerProvider).jobs.single;
    expect(restored.status, DownloadStatus.complete);
    expect(restored.children.first.status, DownloadStatus.complete);
    expect(restored.children.first.downloadedFilePath, endsWith('One.mp3'));
    expect(restored.children.last.status, DownloadStatus.ready);
    expect(restored.children.last.downloadedFilePath, isNull);
  });

  test(
    'cancelled selected playlist download stays stopped after late error',
    () async {
      final fakeService = _FakeYtDlpService();
      final container = ProviderContainer(
        overrides: [
          queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
          ytDlpDownloadServiceProvider.overrideWith(
            (ref, executable) => fakeService,
          ),
        ],
      );
      addTearDown(container.dispose);

      final job = _job('playlist').copyWith(
        children: const [
          DownloadItem(
            id: 'entry:one',
            kind: DownloadItemKind.playlistEntry,
            title: 'One',
            url: 'https://example.com/watch/one',
            status: DownloadStatus.ready,
            progress: 0,
          ),
        ],
      );
      container.read(queueControllerProvider.notifier).insertFirst(job);

      final startFuture = container
          .read(downloadControllerProvider.notifier)
          .start(
            job: job,
            toolSet: const ToolSet(
              ytDlp: ToolInfo.available(path: '/tools/yt-dlp', version: 'test'),
              ffmpeg: ToolInfo.missing(),
              ffprobe: ToolInfo.missing(),
            ),
            outputDirectory: '/tmp/Fetchdeck',
            authentication: YtDlpAuthentication.none,
            reportStatus: (_) {},
            cannotUseYtDlpMessage: () => 'yt-dlp unavailable',
          );

      await _waitUntil(() => fakeService.sessions.length == 1);
      fakeService.sessions.single.emitErrorOnCancel = true;
      container
          .read(downloadControllerProvider.notifier)
          .cancel(job, reportStatus: (_) {});
      await startFuture;

      final restored = container.read(queueControllerProvider).jobs.single;
      expect(restored.status, DownloadStatus.stopped);
      expect(restored.eta, 'Stopped');
      expect(restored.error, isNull);
      expect(restored.children.single.status, DownloadStatus.ready);
      expect(
        restored.logLines,
        isNot(contains(startsWith('Selected child download failed:'))),
      );
    },
  );

  test('downloads selected chapter children with yt-dlp sections', () async {
    final fakeService = _FakeYtDlpService();
    final container = ProviderContainer(
      overrides: [
        queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
        ytDlpDownloadServiceProvider.overrideWith(
          (ref, executable) => fakeService,
        ),
      ],
    );
    addTearDown(container.dispose);

    final job = _job('chapters').copyWith(
      children: const [
        DownloadItem(
          id: 'chapter:1',
          kind: DownloadItemKind.chapter,
          title: 'Intro',
          url: 'https://example.com/chapters',
          startTime: Duration(seconds: 10),
          endTime: Duration(seconds: 70),
          duration: Duration(seconds: 60),
          status: DownloadStatus.ready,
          progress: 0,
        ),
      ],
    );
    container.read(queueControllerProvider.notifier).insertFirst(job);

    final startFuture = container
        .read(downloadControllerProvider.notifier)
        .start(
          job: job,
          toolSet: const ToolSet(
            ytDlp: ToolInfo.available(path: '/tools/yt-dlp', version: 'test'),
            ffmpeg: ToolInfo.missing(),
            ffprobe: ToolInfo.missing(),
          ),
          outputDirectory: '/tmp/Fetchdeck',
          authentication: YtDlpAuthentication.none,
          reportStatus: (_) {},
          cannotUseYtDlpMessage: () => 'yt-dlp unavailable',
        );

    await _waitUntil(() => fakeService.sessions.length == 1);
    expect(fakeService.urls, ['https://example.com/chapters']);
    expect(fakeService.downloadSections, ['*10.000-70.000']);
    expect(fakeService.outputTemplates.single, '01 - Intro.%(ext)s');
    fakeService.sessions.single.output(
      '/tmp/Fetchdeck/chapters/01 - Intro.mp3',
    );
    fakeService.sessions.single.complete();
    await startFuture;
  });

  test('failed downloads keep the finished timestamp', () async {
    final fakeService = _FakeYtDlpService();
    final container = ProviderContainer(
      overrides: [
        queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
        ytDlpDownloadServiceProvider.overrideWith(
          (ref, executable) => fakeService,
        ),
      ],
    );
    addTearDown(container.dispose);

    final job = _job('job-1');
    container.read(queueControllerProvider.notifier).insertFirst(job);

    await container
        .read(downloadControllerProvider.notifier)
        .start(
          job: job,
          toolSet: const ToolSet(
            ytDlp: ToolInfo.available(path: '/tools/yt-dlp', version: 'test'),
            ffmpeg: ToolInfo.missing(),
            ffprobe: ToolInfo.missing(),
          ),
          outputDirectory: '/tmp/Fetchdeck',
          authentication: YtDlpAuthentication.none,
          reportStatus: (_) {},
          cannotUseYtDlpMessage: () => 'yt-dlp unavailable',
        );

    fakeService.sessions.single.fail('Network error');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final restored = container.read(queueControllerProvider).jobs.single;
    expect(restored.status, DownloadStatus.failed);
    expect(restored.startedAt, isNotNull);
    expect(restored.completedAt, isNotNull);
  });

  test(
    'configured browser cookies are not sent on the first download attempt',
    () async {
      final fakeService = _FakeYtDlpService();
      final container = ProviderContainer(
        overrides: [
          queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
          ytDlpDownloadServiceProvider.overrideWith(
            (ref, executable) => fakeService,
          ),
        ],
      );
      addTearDown(container.dispose);

      final job = _job('job-1');
      container.read(queueControllerProvider.notifier).insertFirst(job);

      await container
          .read(downloadControllerProvider.notifier)
          .start(
            job: job,
            toolSet: const ToolSet(
              ytDlp: ToolInfo.available(path: '/tools/yt-dlp', version: 'test'),
              ffmpeg: ToolInfo.missing(),
              ffprobe: ToolInfo.missing(),
            ),
            outputDirectory: '/tmp/Fetchdeck',
            authentication: const YtDlpAuthentication(
              useBrowserCookies: true,
              browser: BrowserCookieSource.chrome,
              browserProfile: 'Profile 1',
            ),
            reportStatus: (_) {},
            cannotUseYtDlpMessage: () => 'yt-dlp unavailable',
          );

      expect(fakeService.authentications.single, YtDlpAuthentication.none);
    },
  );

  test('auth failures retry once with configured browser cookies', () async {
    final fakeService = _FakeYtDlpService();
    final container = ProviderContainer(
      overrides: [
        queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
        ytDlpDownloadServiceProvider.overrideWith(
          (ref, executable) => fakeService,
        ),
      ],
    );
    addTearDown(container.dispose);

    final authentication = const YtDlpAuthentication(
      useBrowserCookies: true,
      browser: BrowserCookieSource.chrome,
      browserProfile: 'Profile 1',
    );
    final job = _job('job-1');
    container.read(queueControllerProvider.notifier).insertFirst(job);

    await container
        .read(downloadControllerProvider.notifier)
        .start(
          job: job,
          toolSet: const ToolSet(
            ytDlp: ToolInfo.available(path: '/tools/yt-dlp', version: 'test'),
            ffmpeg: ToolInfo.missing(),
            ffprobe: ToolInfo.missing(),
          ),
          outputDirectory: '/tmp/Fetchdeck',
          authentication: authentication,
          reportStatus: (_) {},
          cannotUseYtDlpMessage: () => 'yt-dlp unavailable',
        );

    fakeService.sessions.single.fail('Private video. Sign in to confirm.');
    await _waitUntil(() => fakeService.sessions.length == 2);

    expect(fakeService.authentications, [
      YtDlpAuthentication.none,
      authentication,
    ]);
    expect(fakeService.sessions, hasLength(2));
    expect(
      container.read(queueControllerProvider).jobs.single.logLines,
      contains(
        'Download requires authentication. Retrying with browser cookies.',
      ),
    );
  });

  test('cancel removes a queued job from the pending scheduler', () async {
    final fakeService = _FakeYtDlpService();
    final container = ProviderContainer(
      overrides: [
        queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
        ytDlpDownloadServiceProvider.overrideWith(
          (ref, executable) => fakeService,
        ),
      ],
    );
    addTearDown(container.dispose);

    final queue = container.read(queueControllerProvider.notifier);
    queue.insertFirst(_job('third'));
    queue.insertFirst(_job('second'));
    queue.insertFirst(_job('first'));

    await container
        .read(downloadControllerProvider.notifier)
        .startAll(
          jobs: container.read(queueControllerProvider).jobs,
          toolSet: const ToolSet(
            ytDlp: ToolInfo.available(path: '/tools/yt-dlp', version: 'test'),
            ffmpeg: ToolInfo.missing(),
            ffprobe: ToolInfo.missing(),
          ),
          outputDirectory: '/tmp/Fetchdeck',
          concurrencyLimit: DownloadConcurrencyLimit.one,
          authentication: YtDlpAuthentication.none,
          reportStatus: (_) {},
          cannotUseYtDlpMessage: () => 'yt-dlp unavailable',
        );

    final queuedJob = container.read(queueControllerProvider).jobs[1];
    container
        .read(downloadControllerProvider.notifier)
        .cancel(queuedJob, reportStatus: (_) {});

    expect(
      container.read(queueControllerProvider).jobs.map((job) => job.status),
      [DownloadStatus.downloading, DownloadStatus.ready, DownloadStatus.queued],
    );

    fakeService.sessions.first.complete();
    await _waitUntil(() => fakeService.sessions.length == 2);

    expect(fakeService.sessions, hasLength(2));
    expect(fakeService.urls, [
      'https://example.com/first',
      'https://example.com/third',
    ]);
    expect(
      container.read(queueControllerProvider).jobs[1].logLines,
      contains('Download cancelled.'),
    );
    expect(
      container.read(queueControllerProvider).jobs[1].status,
      DownloadStatus.ready,
    );
    expect(
      container.read(queueControllerProvider).jobs[2].status,
      DownloadStatus.downloading,
    );
  });
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

Future<void> _waitUntil(bool Function() condition) async {
  for (var index = 0; index < 20; index++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _FakeYtDlpService extends YtDlpService {
  _FakeYtDlpService() : super(executable: '/fake/yt-dlp');

  final sessions = <_FakeDownloadSession>[];
  final urls = <String>[];
  final authentications = <YtDlpAuthentication>[];
  final outputDirectories = <String>[];
  final downloadSections = <String?>[];
  final outputTemplates = <String?>[];

  @override
  Future<YtDlpDownloadSession> startDownload({
    required String url,
    required PresetDefinition preset,
    required String outputDirectory,
    required bool isPlaylist,
    String? ffmpegPath,
    String? selectedFormatId,
    String? downloadSection,
    String? outputTemplate,
    YtDlpAuthentication authentication = YtDlpAuthentication.none,
  }) async {
    final session = _FakeDownloadSession();
    urls.add(url);
    authentications.add(authentication);
    outputDirectories.add(outputDirectory);
    downloadSections.add(downloadSection);
    outputTemplates.add(outputTemplate);
    sessions.add(session);
    return YtDlpDownloadSession(
      process: _FakeProcess(),
      events: session.controller.stream,
      onCancel: session.cancel,
    );
  }
}

class _PendingYtDlpService extends YtDlpService {
  _PendingYtDlpService() : super(executable: '/fake/yt-dlp');

  final _completer = Completer<YtDlpDownloadSession>();

  @override
  Future<YtDlpDownloadSession> startDownload({
    required String url,
    required PresetDefinition preset,
    required String outputDirectory,
    required bool isPlaylist,
    String? ffmpegPath,
    String? selectedFormatId,
    String? downloadSection,
    String? outputTemplate,
    YtDlpAuthentication authentication = YtDlpAuthentication.none,
  }) {
    return _completer.future;
  }

  void completeStart() {
    final session = _FakeDownloadSession();
    _completer.complete(
      YtDlpDownloadSession(
        process: _FakeProcess(),
        events: session.controller.stream,
        onCancel: session.cancel,
      ),
    );
  }
}

class _FakeDownloadSession {
  final controller = StreamController<DownloadEvent>();
  bool emitErrorOnCancel = false;

  void progress(DownloadProgress progress) {
    controller.add(DownloadProgressEvent(progress));
  }

  void output(String path) {
    controller.add(DownloadOutputEvent(path));
  }

  void complete() {
    controller.add(const DownloadCompleteEvent());
    unawaited(controller.close());
  }

  void fail(String message) {
    controller.add(DownloadErrorEvent(message));
    unawaited(controller.close());
  }

  void cancel() {
    if (emitErrorOnCancel) {
      controller.add(const DownloadErrorEvent('Process terminated.'));
    }
    unawaited(controller.close());
  }
}

class _FakeProcess implements Process {
  @override
  int get pid => 1;

  @override
  Future<int> get exitCode => const Stream<int>.empty().first;

  @override
  IOSink get stdin => IOSink(StreamController<List<int>>().sink);

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
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
    mediaInfo: MediaInfo(
      title: id,
      webpageUrl: 'https://example.com/$id',
      extractor: 'Example',
      formatCount: 1,
    ),
  );
}
