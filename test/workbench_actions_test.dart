import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/features/downloads/application/queue_controller.dart';
import 'package:yt_dlp_desktop/features/shell/application/navigation_controller.dart';
import 'package:yt_dlp_desktop/features/shell/application/status_controller.dart';
import 'package:yt_dlp_desktop/features/shell/application/workbench_actions.dart';
import 'package:yt_dlp_desktop/models/download_models.dart';
import 'package:yt_dlp_desktop/services/queue/queue_repository.dart';

void main() {
  test('selectSection updates navigation and visible selection', () {
    final container = _container();
    addTearDown(container.dispose);

    final queue = container.read(queueControllerProvider.notifier);
    queue.insertFirst(_job('ready', DownloadStatus.ready));
    queue.insertFirst(_job('complete', DownloadStatus.complete));

    container.read(workbenchActionsProvider).selectSection('Downloads');

    expect(container.read(navigationControllerProvider), 'Downloads');
    expect(container.read(queueControllerProvider).selectedJobId, 'complete');
  });

  test('setJobFormat updates selected format and reports status', () {
    final container = _container();
    addTearDown(container.dispose);

    final job = _job('ready', DownloadStatus.ready);
    container.read(queueControllerProvider.notifier).insertFirst(job);

    container.read(workbenchActionsProvider).setJobFormat(job, '251');

    final updatedJob = container.read(queueControllerProvider).jobs.single;
    expect(updatedJob.selectedFormatId, '251');
    expect(
      container.read(statusControllerProvider),
      'Selected format 251 for ready.',
    );
  });

  test(
    'revealOutput reports missing output path without file actions',
    () async {
      final container = _container();
      addTearDown(container.dispose);

      await container
          .read(workbenchActionsProvider)
          .revealOutput(_job('ready', DownloadStatus.ready));

      expect(
        container.read(statusControllerProvider),
        'No output folder is available for ready.',
      );
    },
  );
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
