import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/features/downloads/application/queue_controller.dart';
import 'package:yt_dlp_desktop/features/split_editor/application/split_segment_export_controller.dart';
import 'package:yt_dlp_desktop/models/download_models.dart';
import 'package:yt_dlp_desktop/services/ffmpeg/ffmpeg_split_service.dart';
import 'package:yt_dlp_desktop/services/queue/queue_repository.dart';
import 'package:yt_dlp_desktop/services/tools/tool_discovery.dart';

void main() {
  test('exports selected manual segments into the job output folder', () async {
    final outputDirectory = await Directory.systemTemp.createTemp(
      'fetchdeck-split-export-',
    );
    addTearDown(() => outputDirectory.delete(recursive: true));
    final sourceFile = File('${outputDirectory.path}/source.mp3')
      ..writeAsStringSync('audio');

    final fakeService = _FakeFfmpegSplitService();
    final container = ProviderContainer(
      overrides: [
        queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
        splitSegmentExportServiceProvider.overrideWith(
          (ref, executable) => fakeService,
        ),
      ],
    );
    addTearDown(container.dispose);

    final job = _job(sourceFilePath: sourceFile.path);
    container.read(queueControllerProvider.notifier).insertFirst(job);

    await container
        .read(splitSegmentExportControllerProvider.notifier)
        .start(
          job: job,
          toolSet: const ToolSet(
            ytDlp: ToolInfo.missing(),
            ffmpeg: ToolInfo.available(path: '/tools/ffmpeg', version: 'test'),
            ffprobe: ToolInfo.missing(),
          ),
          outputDirectory: outputDirectory.path,
          reportStatus: (_) {},
        );

    final restored = container.read(queueControllerProvider).jobs.single;
    final destination =
        '${outputDirectory.path}${Platform.pathSeparator}Long Mix';
    expect(restored.status, DownloadStatus.complete);
    expect(restored.outputPath, destination);
    expect(restored.children.first.status, DownloadStatus.complete);
    expect(restored.children.first.downloadedFilePath, endsWith('Opening.mp3'));
    expect(restored.children.last.status, DownloadStatus.ready);
    expect(restored.children.last.downloadedFilePath, isNull);
    expect(fakeService.requests, hasLength(1));
    expect(fakeService.requests.single.sourceFilePath, sourceFile.path);
    expect(fakeService.requests.single.title, 'Opening');
    expect(fakeService.requests.single.startTime, Duration.zero);
    expect(fakeService.requests.single.duration, const Duration(minutes: 3));
    expect(
      fakeService.requests.single.fadeDuration,
      const Duration(milliseconds: 250),
    );
  });

  test(
    'marks the active segment failed and leaves completed work intact',
    () async {
      final outputDirectory = await Directory.systemTemp.createTemp(
        'fetchdeck-split-export-',
      );
      addTearDown(() => outputDirectory.delete(recursive: true));
      final sourceFile = File('${outputDirectory.path}/source.mp3')
        ..writeAsStringSync('audio');

      final fakeService = _FakeFfmpegSplitService()..failNext = true;
      final container = ProviderContainer(
        overrides: [
          queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
          splitSegmentExportServiceProvider.overrideWith(
            (ref, executable) => fakeService,
          ),
        ],
      );
      addTearDown(container.dispose);

      final job = _job(sourceFilePath: sourceFile.path, secondSelected: true)
          .copyWith(
            children: [
              _segment(
                id: 'segment:1',
                title: 'Opening',
                sourceFilePath: sourceFile.path,
                start: Duration.zero,
                end: const Duration(minutes: 3),
              ),
              _segment(
                id: 'segment:2',
                title: 'Closing',
                sourceFilePath: sourceFile.path,
                start: const Duration(minutes: 3),
                end: const Duration(minutes: 6),
              ),
            ],
          );
      container.read(queueControllerProvider.notifier).insertFirst(job);

      await container
          .read(splitSegmentExportControllerProvider.notifier)
          .start(
            job: job,
            toolSet: const ToolSet(
              ytDlp: ToolInfo.missing(),
              ffmpeg: ToolInfo.available(
                path: '/tools/ffmpeg',
                version: 'test',
              ),
              ffprobe: ToolInfo.missing(),
            ),
            outputDirectory: outputDirectory.path,
            reportStatus: (_) {},
          );

      final restored = container.read(queueControllerProvider).jobs.single;
      expect(restored.status, DownloadStatus.failed);
      expect(restored.children.first.status, DownloadStatus.failed);
      expect(restored.children.first.error, 'ffmpeg exploded');
      expect(restored.children.last.status, DownloadStatus.ready);
    },
  );

  test(
    'updates child and parent progress while segment is exporting',
    () async {
      final outputDirectory = await Directory.systemTemp.createTemp(
        'fetchdeck-split-export-',
      );
      addTearDown(() => outputDirectory.delete(recursive: true));
      final sourceFile = File('${outputDirectory.path}/source.mp3')
        ..writeAsStringSync('audio');

      final fakeService = _FakeFfmpegSplitService()..completeManually = true;
      final container = ProviderContainer(
        overrides: [
          queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
          splitSegmentExportServiceProvider.overrideWith(
            (ref, executable) => fakeService,
          ),
        ],
      );
      addTearDown(container.dispose);

      final job = _job(sourceFilePath: sourceFile.path);
      container.read(queueControllerProvider.notifier).insertFirst(job);

      final exportFuture = container
          .read(splitSegmentExportControllerProvider.notifier)
          .start(
            job: job,
            toolSet: const ToolSet(
              ytDlp: ToolInfo.missing(),
              ffmpeg: ToolInfo.available(
                path: '/tools/ffmpeg',
                version: 'test',
              ),
              ffprobe: ToolInfo.missing(),
            ),
            outputDirectory: outputDirectory.path,
            reportStatus: (_) {},
          );

      await _waitUntil(() => fakeService.sessions.isNotEmpty);
      fakeService.sessions.single.progress.add(0.5);
      await Future<void>.delayed(Duration.zero);

      var restored = container.read(queueControllerProvider).jobs.single;
      expect(restored.status, DownloadStatus.downloading);
      expect(restored.progress, 0.5);
      expect(restored.children.first.progress, 0.5);

      fakeService.sessions.single.complete();
      await exportFuture;

      restored = container.read(queueControllerProvider).jobs.single;
      expect(restored.status, DownloadStatus.complete);
      expect(restored.children.first.progress, 1);
    },
  );

  test(
    'retry exports only selected incomplete segments with original numbering',
    () async {
      final outputDirectory = await Directory.systemTemp.createTemp(
        'fetchdeck-split-export-',
      );
      addTearDown(() => outputDirectory.delete(recursive: true));
      final sourceFile = File('${outputDirectory.path}/source.mp3')
        ..writeAsStringSync('audio');
      final exportedDirectory = Directory(
        '${outputDirectory.path}${Platform.pathSeparator}Long Mix',
      )..createSync();
      final exportedOpening = File(
        '${exportedDirectory.path}${Platform.pathSeparator}01 - Opening.mp3',
      )..writeAsStringSync('audio');

      final fakeService = _FakeFfmpegSplitService();
      final container = ProviderContainer(
        overrides: [
          queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
          splitSegmentExportServiceProvider.overrideWith(
            (ref, executable) => fakeService,
          ),
        ],
      );
      addTearDown(container.dispose);

      final job = _job(sourceFilePath: sourceFile.path, secondSelected: true)
          .copyWith(
            status: DownloadStatus.failed,
            progress: 0.5,
            eta: '1 of 2 exported',
            children: [
              _segment(
                id: 'segment:1',
                title: 'Opening',
                sourceFilePath: sourceFile.path,
                start: Duration.zero,
                end: const Duration(minutes: 3),
              ).copyWith(
                status: DownloadStatus.complete,
                progress: 1,
                downloadedFilePath: exportedOpening.path,
              ),
              _segment(
                id: 'segment:2',
                title: 'Closing',
                sourceFilePath: sourceFile.path,
                start: const Duration(minutes: 3),
                end: const Duration(minutes: 6),
              ).copyWith(
                status: DownloadStatus.failed,
                error: 'Previous failure',
              ),
            ],
          );
      container.read(queueControllerProvider.notifier).insertFirst(job);

      await container
          .read(splitSegmentExportControllerProvider.notifier)
          .start(
            job: job,
            toolSet: const ToolSet(
              ytDlp: ToolInfo.missing(),
              ffmpeg: ToolInfo.available(
                path: '/tools/ffmpeg',
                version: 'test',
              ),
              ffprobe: ToolInfo.missing(),
            ),
            outputDirectory: outputDirectory.path,
            reportStatus: (_) {},
          );

      final restored = container.read(queueControllerProvider).jobs.single;
      expect(restored.status, DownloadStatus.complete);
      expect(fakeService.requests, hasLength(1));
      expect(
        fakeService.requests.single.outputFilePath,
        endsWith('02 - Closing.mp3'),
      );
      expect(
        restored.children.first.downloadedFilePath,
        endsWith('01 - Opening.mp3'),
      );
      expect(
        restored.children.last.downloadedFilePath,
        endsWith('02 - Closing.mp3'),
      );
    },
  );

  test(
    're-exports completed manual segments when the output file is missing',
    () async {
      final outputDirectory = await Directory.systemTemp.createTemp(
        'fetchdeck-split-export-',
      );
      addTearDown(() => outputDirectory.delete(recursive: true));
      final sourceFile = File('${outputDirectory.path}/source.mp3')
        ..writeAsStringSync('audio');

      final fakeService = _FakeFfmpegSplitService();
      final container = ProviderContainer(
        overrides: [
          queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
          splitSegmentExportServiceProvider.overrideWith(
            (ref, executable) => fakeService,
          ),
        ],
      );
      addTearDown(container.dispose);

      final missingExport =
          '${outputDirectory.path}${Platform.pathSeparator}Long Mix'
          '${Platform.pathSeparator}01 - Opening.mp3';
      final job = _job(sourceFilePath: sourceFile.path, secondSelected: true)
          .copyWith(
            status: DownloadStatus.complete,
            progress: 1,
            eta: 'Complete',
            children: [
              _segment(
                id: 'segment:1',
                title: 'Opening',
                sourceFilePath: sourceFile.path,
                start: Duration.zero,
                end: const Duration(minutes: 3),
              ).copyWith(
                status: DownloadStatus.complete,
                progress: 1,
                downloadedFilePath: missingExport,
              ),
              _segment(
                id: 'segment:2',
                title: 'Closing',
                sourceFilePath: sourceFile.path,
                start: const Duration(minutes: 3),
                end: const Duration(minutes: 6),
              ).copyWith(status: DownloadStatus.complete, progress: 1),
            ],
          );
      container.read(queueControllerProvider.notifier).insertFirst(job);

      await container
          .read(splitSegmentExportControllerProvider.notifier)
          .start(
            job: job,
            toolSet: const ToolSet(
              ytDlp: ToolInfo.missing(),
              ffmpeg: ToolInfo.available(
                path: '/tools/ffmpeg',
                version: 'test',
              ),
              ffprobe: ToolInfo.missing(),
            ),
            outputDirectory: outputDirectory.path,
            reportStatus: (_) {},
          );

      expect(fakeService.requests, hasLength(2));
      expect(fakeService.requests.first.title, 'Opening');
      expect(
        fakeService.requests.first.outputFilePath,
        endsWith('01 - Opening.mp3'),
      );
      expect(fakeService.requests.last.title, 'Closing');
    },
  );

  test('fails before export when the split source file is missing', () async {
    final outputDirectory = await Directory.systemTemp.createTemp(
      'fetchdeck-split-export-',
    );
    addTearDown(() => outputDirectory.delete(recursive: true));

    final fakeService = _FakeFfmpegSplitService();
    final container = ProviderContainer(
      overrides: [
        queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
        splitSegmentExportServiceProvider.overrideWith(
          (ref, executable) => fakeService,
        ),
      ],
    );
    addTearDown(container.dispose);

    final missingSource =
        '${outputDirectory.path}${Platform.pathSeparator}missing-source.mp3';
    final job = _job(sourceFilePath: missingSource);
    container.read(queueControllerProvider.notifier).insertFirst(job);

    await container
        .read(splitSegmentExportControllerProvider.notifier)
        .start(
          job: job,
          toolSet: const ToolSet(
            ytDlp: ToolInfo.missing(),
            ffmpeg: ToolInfo.available(path: '/tools/ffmpeg', version: 'test'),
            ffprobe: ToolInfo.missing(),
          ),
          outputDirectory: outputDirectory.path,
          reportStatus: (_) {},
        );

    final restored = container.read(queueControllerProvider).jobs.single;
    expect(restored.status, DownloadStatus.failed);
    expect(restored.children.first.status, DownloadStatus.failed);
    expect(
      restored.children.first.error,
      'Split source file no longer exists: $missingSource',
    );
    expect(fakeService.requests, isEmpty);
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
  for (var index = 0; index < 20; index += 1) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

DownloadJob _job({
  required String sourceFilePath,
  bool secondSelected = false,
}) {
  return DownloadJob(
    id: 'job-1',
    url: 'https://example.com/video',
    title: 'Long Mix',
    source: 'Example',
    preset: PresetDefinition.defaultPreset,
    status: DownloadStatus.ready,
    progress: 0,
    eta: 'Ready',
    splitSourceFilePath: sourceFilePath,
    mediaInfo: const MediaInfo(
      title: 'Long Mix',
      webpageUrl: 'https://example.com/video',
      extractor: 'Example',
      formatCount: 1,
      duration: Duration(minutes: 6),
    ),
    children: [
      _segment(
        id: 'segment:1',
        title: 'Opening',
        sourceFilePath: sourceFilePath,
        start: Duration.zero,
        end: Duration(minutes: 3),
      ),
      _segment(
        id: 'segment:2',
        title: 'Closing',
        sourceFilePath: sourceFilePath,
        start: Duration(minutes: 3),
        end: Duration(minutes: 6),
        isSelected: secondSelected,
      ),
    ],
  );
}

DownloadItem _segment({
  required String id,
  required String title,
  required String sourceFilePath,
  required Duration start,
  required Duration end,
  bool isSelected = true,
}) {
  return DownloadItem(
    id: id,
    kind: DownloadItemKind.manualSegment,
    title: title,
    status: DownloadStatus.ready,
    progress: 0,
    sourceFilePath: sourceFilePath,
    startTime: start,
    endTime: end,
    duration: end - start,
    fadeDuration: const Duration(milliseconds: 250),
    isSelected: isSelected,
  );
}

class _FakeFfmpegSplitService extends FfmpegSplitService {
  _FakeFfmpegSplitService() : super(executable: '/fake/ffmpeg');

  final requests = <_ExportRequest>[];
  final sessions = <_FakeFfmpegSplitSession>[];
  bool failNext = false;
  bool completeManually = false;

  @override
  Future<FfmpegSplitSession> startExport({
    required String sourceFilePath,
    required String outputFilePath,
    required String title,
    required Duration startTime,
    required Duration duration,
    required Duration fadeDuration,
  }) async {
    requests.add(
      _ExportRequest(
        sourceFilePath: sourceFilePath,
        outputFilePath: outputFilePath,
        title: title,
        startTime: startTime,
        duration: duration,
        fadeDuration: fadeDuration,
      ),
    );
    if (failNext) {
      failNext = false;
      throw const FfmpegSplitException('ffmpeg exploded');
    }
    if (completeManually) {
      final session = _FakeFfmpegSplitSession();
      sessions.add(session);
      return FfmpegSplitSession(
        process: _FakeProcess(),
        progress: session.progress.stream,
        completed: session.completed.future,
        onCancel: session.cancel,
      );
    }
    return FfmpegSplitSession(
      process: _FakeProcess(),
      progress: const Stream<double>.empty(),
      completed: Future<void>.value(),
      onCancel: () {},
    );
  }
}

class _FakeFfmpegSplitSession {
  final progress = StreamController<double>.broadcast();
  final completed = Completer<void>();

  void complete() {
    unawaited(progress.close());
    completed.complete();
  }

  void cancel() {
    unawaited(progress.close());
    if (!completed.isCompleted) completed.complete();
  }
}

class _ExportRequest {
  const _ExportRequest({
    required this.sourceFilePath,
    required this.outputFilePath,
    required this.title,
    required this.startTime,
    required this.duration,
    required this.fadeDuration,
  });

  final String sourceFilePath;
  final String outputFilePath;
  final String title;
  final Duration startTime;
  final Duration duration;
  final Duration fadeDuration;
}

class _FakeProcess implements Process {
  @override
  int get pid => 1;

  @override
  Future<int> get exitCode => Future<int>.value(0);

  @override
  IOSink get stdin => IOSink(StreamController<List<int>>().sink);

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}
