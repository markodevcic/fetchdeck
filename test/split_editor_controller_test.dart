import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/features/downloads/application/queue_controller.dart';
import 'package:yt_dlp_desktop/features/shell/application/status_controller.dart';
import 'package:yt_dlp_desktop/features/split_editor/application/silence_detection_controller.dart';
import 'package:yt_dlp_desktop/features/split_editor/application/split_audio_controller.dart';
import 'package:yt_dlp_desktop/features/split_editor/application/split_editor_controller.dart';
import 'package:yt_dlp_desktop/models/download_models.dart';
import 'package:yt_dlp_desktop/services/ffmpeg/ffmpeg_silence_detection_service.dart';
import 'package:yt_dlp_desktop/services/queue/queue_repository.dart';
import 'package:yt_dlp_desktop/services/tools/tool_discovery.dart';

void main() {
  test('opens with default marker and source metadata', () {
    final container = _container();
    addTearDown(container.dispose);

    container.read(splitEditorControllerProvider.notifier).open(_job());

    final state = container.read(splitEditorControllerProvider);
    expect(state.jobId, 'job-1');
    expect(state.sourceFilePath, '/tmp/source.mp3');
    expect(state.duration, const Duration(minutes: 12));
    expect(state.markers.single.position, Duration.zero);
    expect(state.markers.single.title, 'Track 01');
  });

  test('prefers prepared split source over final download file', () {
    final container = _container();
    addTearDown(container.dispose);

    container
        .read(splitEditorControllerProvider.notifier)
        .open(
          _job().copyWith(
            downloadedFilePath: '/tmp/final.mp3',
            splitSourceFilePath: '/tmp/editor-source.mp3',
          ),
        );

    expect(
      container.read(splitEditorControllerProvider).sourceFilePath,
      '/tmp/editor-source.mp3',
    );
  });

  test('adds renames removes markers and updates fade', () {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(splitEditorControllerProvider.notifier);
    controller.open(_job());
    controller.addMarker(const Duration(minutes: 3));

    var state = container.read(splitEditorControllerProvider);
    final addedMarker = state.markers.last;
    expect(state.markers, hasLength(2));
    expect(addedMarker.position, const Duration(minutes: 3));

    controller.renameMarker(addedMarker.id, 'Amazing Grace');
    controller.setFadeDuration(const Duration(milliseconds: 250));

    state = container.read(splitEditorControllerProvider);
    expect(state.markers.last.title, 'Amazing Grace');
    expect(state.fadeDuration, const Duration(milliseconds: 250));

    controller.removeMarker(addedMarker.id);

    state = container.read(splitEditorControllerProvider);
    expect(state.markers, hasLength(1));
  });

  test(
    'removes duplicate zero marker while keeping default marker protected',
    () {
      final container = _container();
      addTearDown(container.dispose);

      final controller = container.read(splitEditorControllerProvider.notifier);
      controller.open(_job());
      controller.addMarker(Duration.zero);

      var state = container.read(splitEditorControllerProvider);
      expect(state.markers, hasLength(2));
      expect(state.validation.markerErrors, isNotEmpty);

      final duplicateZeroMarker = state.markers.last;
      controller.removeMarker(duplicateZeroMarker.id);

      state = container.read(splitEditorControllerProvider);
      expect(state.markers, hasLength(1));
      expect(state.markers.single.id, 'marker:0');

      controller.removeMarker('marker:0');
      expect(
        container.read(splitEditorControllerProvider).markers,
        hasLength(1),
      );
    },
  );

  test('validates marker titles and spacing before apply', () {
    final container = _container();
    addTearDown(container.dispose);

    final job = _job();
    container.read(queueControllerProvider.notifier).insertFirst(job);

    final controller = container.read(splitEditorControllerProvider.notifier);
    controller.open(job);
    controller.addMarker(const Duration(seconds: 1));

    var state = container.read(splitEditorControllerProvider);
    expect(state.canApply, isFalse);
    expect(
      state.validation.markerErrors.values,
      contains('Markers must be at least 2s apart.'),
    );

    final markerId = state.markers.last.id;
    controller.moveMarker(markerId, const Duration(seconds: 4));
    controller.renameMarker(markerId, '');

    state = container.read(splitEditorControllerProvider);
    expect(state.canApply, isFalse);
    expect(state.validation.errorFor(markerId), 'Song title is required.');

    controller.apply();
    expect(container.read(splitEditorControllerProvider).isOpen, isTrue);
    expect(
      container.read(splitEditorControllerProvider).error,
      'Song title is required.',
    );
    expect(
      container.read(queueControllerProvider).jobs.single.children,
      isEmpty,
    );
  });

  test('moves marker timestamp and keeps markers sorted', () {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(splitEditorControllerProvider.notifier);
    controller.open(_job());
    controller.addMarker(const Duration(minutes: 8));
    controller.addMarker(const Duration(minutes: 4));

    final markerId = container
        .read(splitEditorControllerProvider)
        .markers
        .last
        .id;
    controller.moveMarker(markerId, const Duration(minutes: 2));

    final positions = container
        .read(splitEditorControllerProvider)
        .markers
        .map((marker) => marker.position)
        .toList();
    expect(positions, [
      Duration.zero,
      const Duration(minutes: 2),
      const Duration(minutes: 4),
    ]);
  });

  test('adds detected markers while skipping unusable positions', () {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(splitEditorControllerProvider.notifier);
    controller.open(_job());
    controller.addMarker(const Duration(minutes: 4));

    final added = controller.addDetectedMarkers([
      Duration.zero,
      const Duration(minutes: 4, seconds: 1),
      const Duration(minutes: 6),
      const Duration(minutes: 13),
    ]);

    final positions = container
        .read(splitEditorControllerProvider)
        .markers
        .map((marker) => marker.position)
        .toList();
    expect(added, 1);
    expect(positions, [
      Duration.zero,
      const Duration(minutes: 4),
      const Duration(minutes: 6),
    ]);
  });

  test('silence detection previews then accepts detected markers', () async {
    final fakeService = _FakeSilenceDetectionService();
    final container = ProviderContainer(
      overrides: [
        queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
        splitAudioAutoloadEnabledProvider.overrideWithValue(false),
        silenceDetectionServiceProvider(
          '/tools/ffmpeg',
        ).overrideWithValue(fakeService),
      ],
    );
    addTearDown(container.dispose);

    container.read(splitEditorControllerProvider.notifier).open(_job());
    container
        .read(silenceDetectionControllerProvider.notifier)
        .setNoiseThreshold('-40dB');
    container
        .read(silenceDetectionControllerProvider.notifier)
        .setMinimumSilence(const Duration(milliseconds: 1800));

    await container
        .read(silenceDetectionControllerProvider.notifier)
        .detectWith(
          toolSet: const ToolSet(
            ytDlp: ToolInfo.missing(),
            ffmpeg: ToolInfo.available(path: '/tools/ffmpeg', version: 'test'),
            ffprobe: ToolInfo.missing(),
          ),
          reportStatus: container
              .read(statusControllerProvider.notifier)
              .setMessage,
        );

    final state = container.read(splitEditorControllerProvider);
    expect(state.markers.map((marker) => marker.position), [Duration.zero]);
    final detectionState = container.read(silenceDetectionControllerProvider);
    expect(detectionState.candidates.map((candidate) => candidate.position), [
      const Duration(minutes: 3),
      const Duration(minutes: 7),
    ]);
    expect(container.read(statusControllerProvider), 'Found 2 possible cuts.');
    expect(
      container.read(silenceDetectionControllerProvider).isDetecting,
      false,
    );
    expect(fakeService.noiseThreshold, '-40dB');
    expect(fakeService.minimumSilence, const Duration(milliseconds: 1800));

    container
        .read(silenceDetectionControllerProvider.notifier)
        .toggleCandidate(detectionState.candidates.first.id);
    container
        .read(silenceDetectionControllerProvider.notifier)
        .acceptSelectedCandidates(
          reportStatus: container
              .read(statusControllerProvider.notifier)
              .setMessage,
        );

    expect(
      container
          .read(splitEditorControllerProvider)
          .markers
          .map((marker) => marker.position),
      [Duration.zero, const Duration(minutes: 7)],
    );
    expect(
      container.read(silenceDetectionControllerProvider).candidates,
      isEmpty,
    );
    expect(container.read(statusControllerProvider), 'Added 1 silence marker.');
  });

  test('apply stores split plan and generated manual segment children', () {
    final container = _container();
    addTearDown(container.dispose);

    final job = _job();
    container.read(queueControllerProvider.notifier).insertFirst(job);

    final controller = container.read(splitEditorControllerProvider.notifier);
    controller.open(job);
    controller.addMarker(const Duration(minutes: 4));
    final markerId = container
        .read(splitEditorControllerProvider)
        .markers
        .last
        .id;
    controller.renameMarker(markerId, 'Second Song');
    controller.apply();

    final updatedJob = container.read(queueControllerProvider).jobs.single;
    expect(container.read(splitEditorControllerProvider).isOpen, isFalse);
    expect(updatedJob.splitPlan, isNotNull);
    expect(updatedJob.isExpanded, isTrue);
    expect(updatedJob.children, hasLength(2));
    expect(updatedJob.children.first.kind, DownloadItemKind.manualSegment);
    expect(updatedJob.children.first.title, 'Track 01');
    expect(updatedJob.children.last.title, 'Second Song');
    expect(
      container.read(statusControllerProvider),
      'Created 2 split segments. Select the segments and press Export to create files.',
    );
  });
}

ProviderContainer _container() {
  return ProviderContainer(
    overrides: [
      queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
      splitAudioAutoloadEnabledProvider.overrideWithValue(false),
    ],
  );
}

class _FakeSilenceDetectionService extends FfmpegSilenceDetectionService {
  _FakeSilenceDetectionService() : super(executable: '/tools/ffmpeg');

  String? noiseThreshold;
  Duration? minimumSilence;

  @override
  Future<FfmpegSilenceDetectionSession> startDetection({
    required String sourceFilePath,
    required String noiseThreshold,
    required Duration minimumSilence,
    required Duration duration,
  }) async {
    this.noiseThreshold = noiseThreshold;
    this.minimumSilence = minimumSilence;
    return FfmpegSilenceDetectionSession(
      progress: Stream<double>.fromIterable(const [0.25, 1]),
      completed: Future.value(const [
        Duration(minutes: 3),
        Duration(minutes: 7),
      ]),
      onCancel: () {},
    );
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
    title: 'Long Worship Mix',
    source: 'Example',
    preset: PresetDefinition.defaultPreset,
    status: DownloadStatus.ready,
    progress: 0,
    eta: 'Ready',
    downloadedFilePath: '/tmp/source.mp3',
    mediaInfo: const MediaInfo(
      title: 'Long Worship Mix',
      webpageUrl: 'https://example.com/video',
      extractor: 'Example',
      formatCount: 1,
      duration: Duration(minutes: 12),
    ),
  );
}
