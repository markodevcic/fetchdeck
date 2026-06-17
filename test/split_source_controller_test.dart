import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/features/downloads/application/queue_controller.dart';
import 'package:yt_dlp_desktop/features/split_editor/application/split_source_controller.dart';
import 'package:yt_dlp_desktop/models/download_models.dart';
import 'package:yt_dlp_desktop/services/queue/queue_repository.dart';
import 'package:yt_dlp_desktop/services/tools/tool_discovery.dart';
import 'package:yt_dlp_desktop/services/yt_dlp/yt_dlp_authentication.dart';
import 'package:yt_dlp_desktop/services/yt_dlp/yt_dlp_service.dart';

void main() {
  test(
    'prepare downloads a hidden split source without completing the job',
    () async {
      final outputDirectory = await Directory.systemTemp.createTemp(
        'fetchdeck-split-source-',
      );
      addTearDown(() => outputDirectory.delete(recursive: true));

      final fakeService = _FakeYtDlpService();
      final container = ProviderContainer(
        overrides: [
          queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
          splitSourceYtDlpServiceProvider.overrideWith(
            (ref, executable) => fakeService,
          ),
        ],
      );
      addTearDown(container.dispose);

      final job = _job();
      container.read(queueControllerProvider.notifier).insertFirst(job);

      final prepareFuture = container
          .read(splitSourceControllerProvider.notifier)
          .prepare(
            job: job,
            toolSet: const ToolSet(
              ytDlp: ToolInfo.available(path: '/tools/yt-dlp', version: 'test'),
              ffmpeg: ToolInfo.available(
                path: '/tools/ffmpeg',
                version: 'test',
              ),
              ffprobe: ToolInfo.missing(),
            ),
            outputDirectory: outputDirectory.path,
            authentication: YtDlpAuthentication.none,
            reportStatus: (_) {},
            cannotUseYtDlpMessage: () => 'yt-dlp unavailable',
          );

      await _waitUntil(() => fakeService.sessions.length == 1);

      expect(fakeService.sessions, hasLength(1));
      expect(fakeService.isPlaylistValues.single, isFalse);
      expect(
        fakeService.outputDirectories.single,
        '${outputDirectory.path}${Platform.pathSeparator}Long Mix${Platform.pathSeparator}.fetchdeck${Platform.pathSeparator}source',
      );

      final sourcePath =
          '${fakeService.outputDirectories.single}${Platform.pathSeparator}Long Mix.mp3';
      fakeService.sessions.single.output(sourcePath);
      fakeService.sessions.single.complete();

      final preparedJob = await prepareFuture;
      final restored = container.read(queueControllerProvider).jobs.single;
      expect(preparedJob?.id, job.id);
      expect(restored.status, DownloadStatus.ready);
      expect(restored.downloadedFilePath, isNull);
      expect(restored.splitSourceFilePath, sourcePath);
      expect(restored.logLines, contains('Split source prepared: $sourcePath'));
    },
  );

  test('prepare reuses an existing local split source', () async {
    final outputDirectory = await Directory.systemTemp.createTemp(
      'fetchdeck-split-source-',
    );
    addTearDown(() => outputDirectory.delete(recursive: true));
    final sourceFile = File('${outputDirectory.path}/source.mp3');
    await sourceFile.writeAsBytes(const [1, 2, 3]);

    final fakeService = _FakeYtDlpService();
    final container = ProviderContainer(
      overrides: [
        queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
        splitSourceYtDlpServiceProvider.overrideWith(
          (ref, executable) => fakeService,
        ),
      ],
    );
    addTearDown(container.dispose);

    final job = _job().copyWith(splitSourceFilePath: sourceFile.path);

    final preparedJob = await container
        .read(splitSourceControllerProvider.notifier)
        .prepare(
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

    expect(preparedJob, job);
    expect(fakeService.sessions, isEmpty);
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var index = 0; index < 20; index += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
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

DownloadJob _job() {
  return DownloadJob(
    id: 'job-1',
    url: 'https://example.com/video',
    title: 'Long Mix',
    source: 'Example',
    preset: PresetDefinition.defaultPreset,
    status: DownloadStatus.ready,
    progress: 0,
    eta: 'Ready',
    mediaInfo: const MediaInfo(
      title: 'Long Mix',
      webpageUrl: 'https://example.com/video',
      extractor: 'Example',
      formatCount: 1,
      duration: Duration(minutes: 12),
    ),
  );
}

class _FakeYtDlpService extends YtDlpService {
  _FakeYtDlpService() : super(executable: '/fake/yt-dlp');

  final sessions = <_FakeDownloadSession>[];
  final outputDirectories = <String>[];
  final isPlaylistValues = <bool>[];

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
    outputDirectories.add(outputDirectory);
    isPlaylistValues.add(isPlaylist);
    sessions.add(session);
    return YtDlpDownloadSession(
      process: _FakeProcess(),
      events: session.controller.stream,
      onCancel: session.cancel,
    );
  }
}

class _FakeDownloadSession {
  final controller = StreamController<DownloadEvent>();

  void output(String path) {
    controller.add(DownloadOutputEvent(path));
  }

  void complete() {
    controller.add(const DownloadCompleteEvent());
    unawaited(controller.close());
  }

  void cancel() {
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
