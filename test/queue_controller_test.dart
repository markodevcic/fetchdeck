import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/features/downloads/application/queue_controller.dart';
import 'package:yt_dlp_desktop/models/download_models.dart';
import 'package:yt_dlp_desktop/services/queue/queue_repository.dart';

void main() {
  test('downloads view shows all jobs', () {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(queueControllerProvider.notifier);
    controller.insertFirst(_job('ready', DownloadStatus.ready));
    controller.insertFirst(_job('complete', DownloadStatus.complete));

    final state = container.read(queueControllerProvider);

    expect(state.visibleJobs().map((job) => job.id), contains('ready'));
    expect(state.visibleJobs().map((job) => job.id), contains('complete'));
  });

  test('keeps selected job when it is visible in downloads', () {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(queueControllerProvider.notifier);
    controller.insertFirst(_job('ready', DownloadStatus.ready));
    controller.insertFirst(_job('complete', DownloadStatus.complete));

    controller.ensureVisibleSelection();

    expect(container.read(queueControllerProvider).selectedJobId, 'complete');
  });

  test('remove falls back to the next visible job', () {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(queueControllerProvider.notifier);
    final first = _job('first', DownloadStatus.ready);
    final second = _job('second', DownloadStatus.ready);
    controller.insertFirst(second);
    controller.insertFirst(first);

    controller.remove(first);

    final state = container.read(queueControllerProvider);
    expect(state.jobs.map((job) => job.id), ['second']);
    expect(state.selectedJobId, 'second');
  });

  test('finds duplicate urls while ignoring fragments and trailing slash', () {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(queueControllerProvider.notifier);
    controller.insertFirst(_job('existing', DownloadStatus.ready));

    final state = container.read(queueControllerProvider);

    expect(
      state.jobByUrl('https://example.com/existing/#comments')?.id,
      'existing',
    );
  });

  test('filters visible jobs by status and search query', () {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(queueControllerProvider.notifier);
    controller.insertFirst(_job('ready-song', DownloadStatus.ready));
    controller.insertFirst(_job('failed-talk', DownloadStatus.failed));
    controller.insertFirst(_job('complete-song', DownloadStatus.complete));

    controller.setStatusFilter(QueueStatusFilter.failed);
    expect(
      container
          .read(queueControllerProvider)
          .visibleJobs()
          .map((job) => job.id),
      ['failed-talk'],
    );

    controller.setStatusFilter(QueueStatusFilter.all);
    controller.setSearchQuery('song');
    expect(
      container
          .read(queueControllerProvider)
          .visibleJobs()
          .map((job) => job.id),
      ['complete-song', 'ready-song'],
    );
  });

  test('complete filter shows completed downloads', () {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(queueControllerProvider.notifier);
    controller.insertFirst(_job('ready', DownloadStatus.ready));
    controller.insertFirst(_job('complete', DownloadStatus.complete));
    controller.setStatusFilter(QueueStatusFilter.complete);

    expect(
      container
          .read(queueControllerProvider)
          .visibleJobs()
          .map((job) => job.id),
      ['complete'],
    );
  });

  test('filter changes keep selected job visible', () {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(queueControllerProvider.notifier);
    controller.insertFirst(_job('ready', DownloadStatus.ready));
    controller.insertFirst(_job('failed', DownloadStatus.failed));

    controller.selectJob('ready');
    controller.setStatusFilter(QueueStatusFilter.failed);

    expect(container.read(queueControllerProvider).selectedJobId, 'failed');
  });

  test('toggles child selection and expansion', () {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(queueControllerProvider.notifier);
    controller.insertFirst(
      _job('playlist', DownloadStatus.ready).copyWith(
        children: const [
          DownloadItem(
            id: 'entry:one',
            kind: DownloadItemKind.playlistEntry,
            title: 'First',
            status: DownloadStatus.ready,
            progress: 0,
          ),
          DownloadItem(
            id: 'entry:two',
            kind: DownloadItemKind.playlistEntry,
            title: 'Second',
            status: DownloadStatus.ready,
            progress: 0,
          ),
        ],
      ),
    );

    controller.toggleExpanded('playlist');
    controller.setChildSelected(
      jobId: 'playlist',
      childId: 'entry:one',
      isSelected: false,
    );

    var job = container.read(queueControllerProvider).jobs.single;
    expect(job.isExpanded, isTrue);
    expect(job.selectedChildCount, 1);
    expect(job.children.first.isSelected, isFalse);

    controller.setAllChildrenSelected('playlist', false);

    job = container.read(queueControllerProvider).jobs.single;
    expect(job.selectedChildCount, 0);
    expect(job.children.every((child) => !child.isSelected), isTrue);
  });

  test('reconciles stale split export children when source is missing', () {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(queueControllerProvider.notifier);
    final job = _job('split', DownloadStatus.complete).copyWith(
      downloadedFilePath: '/downloads/split/source.mp3',
      splitSourceFilePath: '/downloads/split/source.mp3',
      splitPlan: _splitPlan('/downloads/split/source.mp3'),
      isExpanded: true,
      children: const [
        DownloadItem(
          id: 'segment:1',
          kind: DownloadItemKind.manualSegment,
          title: 'Track 01',
          status: DownloadStatus.ready,
          progress: 0,
        ),
      ],
    );
    controller.insertFirst(job);

    final reconciled = controller.reconcileLocalFilesForJob(job);

    expect(reconciled.status, DownloadStatus.ready);
    expect(reconciled.children, isEmpty);
    expect(reconciled.splitPlan, isNull);
    expect(reconciled.splitSourceFilePath, isNull);
    expect(reconciled.downloadedFilePath, isNull);
    expect(
      container.read(queueControllerProvider).jobs.single.children,
      isEmpty,
    );
  });
}

ProviderContainer _container() {
  return ProviderContainer(
    overrides: [
      queueRepositoryProvider.overrideWithValue(_MemoryQueueRepository()),
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

DownloadJob _job(String id, DownloadStatus status, {DateTime? completedAt}) {
  return DownloadJob(
    id: id,
    url: 'https://example.com/$id',
    title: id,
    source: 'example.com',
    preset: PresetDefinition.defaultPreset,
    status: status,
    progress: status == DownloadStatus.complete ? 1 : 0,
    eta: status.label,
    completedAt: completedAt,
  );
}

SplitPlan _splitPlan(String sourceFilePath) {
  return SplitPlan(
    sourceFilePath: sourceFilePath,
    markers: const [
      SplitMarker(id: 'marker:0', position: Duration.zero, title: 'Track 01'),
      SplitMarker(
        id: 'marker:1',
        position: Duration(minutes: 4),
        title: 'Track 02',
      ),
    ],
    fadeDuration: Duration.zero,
    appliedAt: DateTime.utc(2026, 6, 12, 10),
  );
}
