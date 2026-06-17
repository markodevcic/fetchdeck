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

enum QueueStatusFilter {
  all('All'),
  ready('Ready'),
  downloading('Downloading'),
  failed('Failed'),
  complete('Complete');

  const QueueStatusFilter(this.label);

  final String label;
}

class QueueState {
  const QueueState({
    this.jobs = const [],
    this.selectedJobId,
    this.statusFilter = QueueStatusFilter.all,
    this.searchQuery = '',
  });

  final List<DownloadJob> jobs;
  final String? selectedJobId;
  final QueueStatusFilter statusFilter;
  final String searchQuery;

  List<DownloadJob> visibleJobs() {
    return _filterJobs(List<DownloadJob>.from(jobs));
  }

  DownloadJob? selectedJob() {
    final visible = visibleJobs();
    for (final job in visible) {
      if (job.id == selectedJobId) return job;
    }
    return visible.isEmpty ? null : visible.first;
  }

  DownloadJob? jobByUrl(String url) {
    final normalized = _normalizedUrl(url);
    if (normalized.isEmpty) return null;

    for (final job in jobs) {
      if (_normalizedUrl(job.url) == normalized) return job;
    }
    return null;
  }

  bool canStartVisibleJobs() {
    return visibleJobs().any(
      (job) =>
          job.status == DownloadStatus.ready ||
          job.status == DownloadStatus.stopped ||
          job.status == DownloadStatus.failed,
    );
  }

  QueueState copyWith({List<DownloadJob>? jobs, String? selectedJobId}) {
    return QueueState(
      jobs: jobs ?? this.jobs,
      selectedJobId: selectedJobId ?? this.selectedJobId,
      statusFilter: statusFilter,
      searchQuery: searchQuery,
    );
  }

  QueueState copyWithSelection({required String? selectedJobId}) {
    return QueueState(
      jobs: jobs,
      selectedJobId: selectedJobId,
      statusFilter: statusFilter,
      searchQuery: searchQuery,
    );
  }

  QueueState copyWithFilters({
    QueueStatusFilter? statusFilter,
    String? searchQuery,
    String? selectedJobId,
  }) {
    return QueueState(
      jobs: jobs,
      selectedJobId: selectedJobId ?? this.selectedJobId,
      statusFilter: statusFilter ?? this.statusFilter,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }

  List<DownloadJob> _filterJobs(List<DownloadJob> routeJobs) {
    final statusFiltered = switch (statusFilter) {
      QueueStatusFilter.all => routeJobs,
      QueueStatusFilter.ready =>
        routeJobs
            .where(
              (job) =>
                  job.status == DownloadStatus.ready ||
                  job.status == DownloadStatus.stopped,
            )
            .toList(growable: false),
      QueueStatusFilter.downloading =>
        routeJobs
            .where((job) => job.status == DownloadStatus.downloading)
            .toList(growable: false),
      QueueStatusFilter.failed =>
        routeJobs
            .where((job) => job.status == DownloadStatus.failed)
            .toList(growable: false),
      QueueStatusFilter.complete =>
        routeJobs
            .where((job) => job.status == DownloadStatus.complete)
            .toList(growable: false),
    };
    final query = searchQuery.trim().toLowerCase();
    if (query.isEmpty) return statusFiltered;

    return statusFiltered
        .where((job) {
          final haystack = [
            job.title,
            job.source,
            job.url,
            job.preset.label,
            job.error ?? '',
          ].join(' ').toLowerCase();
          return haystack.contains(query);
        })
        .toList(growable: false);
  }
}

String _normalizedUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return '';

  final parsed = Uri.tryParse(trimmed);
  if (parsed == null || !parsed.hasScheme) return trimmed;

  final normalized = parsed.removeFragment().toString();
  return normalized.endsWith('/')
      ? normalized.substring(0, normalized.length - 1)
      : normalized;
}

class QueueController extends Notifier<QueueState> {
  @override
  QueueState build() => const QueueState();

  Future<int> load() async {
    final restoredJobs = await ref.read(queueRepositoryProvider).load();
    state = QueueState(
      jobs: restoredJobs,
      selectedJobId: restoredJobs.isEmpty ? null : restoredJobs.first.id,
      statusFilter: state.statusFilter,
      searchQuery: state.searchQuery,
    );
    return restoredJobs.length;
  }

  void selectJob(String id) {
    state = state.copyWith(selectedJobId: id);
  }

  void setStatusFilter(QueueStatusFilter filter) {
    state = state.copyWithFilters(statusFilter: filter);
    ensureVisibleSelection();
  }

  void setSearchQuery(String query) {
    state = state.copyWithFilters(searchQuery: query);
    ensureVisibleSelection();
  }

  void ensureVisibleSelection() {
    final visible = state.visibleJobs();
    final visibleIds = visible.map((job) => job.id).toSet();
    if (state.selectedJobId == null ||
        !visibleIds.contains(state.selectedJobId)) {
      state = state.copyWithSelection(
        selectedJobId: visible.isEmpty ? null : visible.first.id,
      );
    }
  }

  DownloadJob reconcileLocalFilesForJob(DownloadJob job) {
    final reconciled = reconcileLocalQueueJobFiles(job);
    if (identical(reconciled, job)) return job;

    replace(job.id, reconciled);
    return reconciled;
  }

  void reconcileLocalFiles() {
    var recoveredAny = false;
    final jobs = [
      for (final job in state.jobs)
        () {
          final reconciled = reconcileLocalQueueJobFiles(job);
          if (!identical(reconciled, job)) recoveredAny = true;
          return reconciled;
        }(),
    ];
    if (!recoveredAny) return;

    state = state.copyWith(jobs: jobs);
    ensureVisibleSelection();
    _persist();
  }

  void insertFirst(DownloadJob job) {
    state = QueueState(
      jobs: [job, ...state.jobs],
      selectedJobId: job.id,
      statusFilter: state.statusFilter,
      searchQuery: state.searchQuery,
    );
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

  void toggleExpanded(String jobId) {
    update(jobId, (job) => job.copyWith(isExpanded: !job.isExpanded));
  }

  void setChildSelected({
    required String jobId,
    required String childId,
    required bool isSelected,
  }) {
    update(jobId, (job) {
      return job.copyWith(
        children: [
          for (final child in job.children)
            child.id == childId
                ? child.copyWith(isSelected: isSelected)
                : child,
        ],
      );
    });
  }

  void setAllChildrenSelected(String jobId, bool isSelected) {
    update(jobId, (job) {
      return job.copyWith(
        children: [
          for (final child in job.children)
            child.copyWith(isSelected: isSelected),
        ],
      );
    });
  }

  void remove(DownloadJob job) {
    final jobs = state.jobs
        .where((candidate) => candidate.id != job.id)
        .toList(growable: false);
    final nextState = state.copyWith(jobs: jobs);
    final visible = nextState.visibleJobs();
    final visibleIds = visible.map((candidate) => candidate.id).toSet();
    final selectedJobId =
        state.selectedJobId == job.id ||
            !visibleIds.contains(state.selectedJobId)
        ? visible.isEmpty
              ? null
              : visible.first.id
        : state.selectedJobId;

    state = QueueState(
      jobs: jobs,
      selectedJobId: selectedJobId,
      statusFilter: state.statusFilter,
      searchQuery: state.searchQuery,
    );
    _persist();
  }

  void _persist() {
    unawaited(ref.read(queueRepositoryProvider).save(state.jobs));
  }
}
