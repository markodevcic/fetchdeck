import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/download_models.dart';
import '../../../services/queue/queue_repository.dart';

final queueRepositoryProvider = Provider<QueueRepository>(
  (ref) => const QueueRepository(),
);

final queueControllerProvider = NotifierProvider<QueueController, QueueState>(
  QueueController.new,
);

class QueueState {
  const QueueState({this.jobs = const [], this.selectedJobId});

  final List<DownloadJob> jobs;
  final String? selectedJobId;

  List<DownloadJob> visibleJobs(String section) {
    return switch (section) {
      'Downloads' =>
        jobs
            .where((job) => job.status != DownloadStatus.complete)
            .toList(growable: false),
      'Library' =>
        jobs
            .where((job) => job.status == DownloadStatus.complete)
            .toList(growable: false),
      'Queue' => List<DownloadJob>.from(jobs),
      _ => List<DownloadJob>.from(jobs),
    };
  }

  DownloadJob? selectedJob(String section) {
    final visible = visibleJobs(section);
    for (final job in visible) {
      if (job.id == selectedJobId) return job;
    }
    return visible.isEmpty ? null : visible.first;
  }

  bool canStartVisibleJobs(String section) {
    return section != 'Library' &&
        visibleJobs(section).any(
          (job) =>
              job.status == DownloadStatus.ready ||
              job.status == DownloadStatus.failed,
        );
  }

  QueueState copyWith({List<DownloadJob>? jobs, String? selectedJobId}) {
    return QueueState(
      jobs: jobs ?? this.jobs,
      selectedJobId: selectedJobId ?? this.selectedJobId,
    );
  }

  QueueState copyWithSelection({required String? selectedJobId}) {
    return QueueState(jobs: jobs, selectedJobId: selectedJobId);
  }
}

class QueueController extends Notifier<QueueState> {
  @override
  QueueState build() => const QueueState();

  Future<int> load() async {
    final restoredJobs = await ref.read(queueRepositoryProvider).load();
    state = QueueState(
      jobs: restoredJobs,
      selectedJobId: restoredJobs.isEmpty ? null : restoredJobs.first.id,
    );
    return restoredJobs.length;
  }

  void selectJob(String id) {
    state = state.copyWith(selectedJobId: id);
  }

  void ensureVisibleSelection(String section) {
    final visible = state.visibleJobs(section);
    final visibleIds = visible.map((job) => job.id).toSet();
    if (state.selectedJobId == null ||
        !visibleIds.contains(state.selectedJobId)) {
      state = state.copyWithSelection(
        selectedJobId: visible.isEmpty ? null : visible.first.id,
      );
    }
  }

  void insertFirst(DownloadJob job) {
    state = QueueState(jobs: [job, ...state.jobs], selectedJobId: job.id);
    _persist();
  }

  void replace(String id, DownloadJob replacement) {
    final index = state.jobs.indexWhere((job) => job.id == id);
    if (index == -1) return;

    final jobs = [...state.jobs];
    jobs[index] = replacement;
    state = state.copyWith(jobs: jobs);
    _persist();
  }

  void update(String id, DownloadJob Function(DownloadJob current) update) {
    final index = state.jobs.indexWhere((job) => job.id == id);
    if (index == -1) return;

    final jobs = [...state.jobs];
    jobs[index] = update(jobs[index]);
    state = state.copyWith(jobs: jobs);
    _persist();
  }

  void remove(DownloadJob job, String section) {
    final jobs = state.jobs
        .where((candidate) => candidate.id != job.id)
        .toList(growable: false);
    final nextState = state.copyWith(jobs: jobs);
    final visible = nextState.visibleJobs(section);
    final visibleIds = visible.map((candidate) => candidate.id).toSet();
    final selectedJobId =
        state.selectedJobId == job.id ||
            !visibleIds.contains(state.selectedJobId)
        ? visible.isEmpty
              ? null
              : visible.first.id
        : state.selectedJobId;

    state = QueueState(jobs: jobs, selectedJobId: selectedJobId);
    _persist();
  }

  void _persist() {
    unawaited(ref.read(queueRepositoryProvider).save(state.jobs));
  }
}
