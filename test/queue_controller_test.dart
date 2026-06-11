import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/features/downloads/application/queue_controller.dart';
import 'package:yt_dlp_desktop/models/download_models.dart';
import 'package:yt_dlp_desktop/services/queue/queue_repository.dart';

void main() {
  test('filters visible jobs by section', () {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(queueControllerProvider.notifier);
    controller.insertFirst(_job('ready', DownloadStatus.ready));
    controller.insertFirst(_job('complete', DownloadStatus.complete));

    final state = container.read(queueControllerProvider);

    expect(
      state.visibleJobs('Downloads').map((job) => job.id),
      contains('ready'),
    );
    expect(
      state.visibleJobs('Downloads').map((job) => job.id),
      isNot(contains('complete')),
    );
    expect(
      state.visibleJobs('Library').map((job) => job.id),
      contains('complete'),
    );
    expect(state.visibleJobs('Queue'), hasLength(2));
  });

  test('keeps selected job visible after changing section', () {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(queueControllerProvider.notifier);
    controller.insertFirst(_job('ready', DownloadStatus.ready));
    controller.insertFirst(_job('complete', DownloadStatus.complete));

    controller.ensureVisibleSelection('Downloads');

    expect(container.read(queueControllerProvider).selectedJobId, 'ready');
  });

  test('remove falls back to the next visible job', () {
    final container = _container();
    addTearDown(container.dispose);

    final controller = container.read(queueControllerProvider.notifier);
    final first = _job('first', DownloadStatus.ready);
    final second = _job('second', DownloadStatus.ready);
    controller.insertFirst(second);
    controller.insertFirst(first);

    controller.remove(first, 'Downloads');

    final state = container.read(queueControllerProvider);
    expect(state.jobs.map((job) => job.id), ['second']);
    expect(state.selectedJobId, 'second');
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

DownloadJob _job(String id, DownloadStatus status) {
  return DownloadJob(
    id: id,
    url: 'https://example.com/$id',
    title: id,
    source: 'example.com',
    preset: PresetDefinition.defaultPreset,
    status: status,
    progress: status == DownloadStatus.complete ? 1 : 0,
    eta: status.label,
  );
}
