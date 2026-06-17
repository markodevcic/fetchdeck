import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../models/download_models.dart';

class QueueRepository {
  const QueueRepository();

  static const _fileName = 'queue.json';
  static Future<void> _saveTail = Future<void>.value();

  Future<List<DownloadJob>> load() async {
    final file = await _queueFile();
    if (!await file.exists()) return const [];

    try {
      final payload = jsonDecode(await file.readAsString());
      if (payload is! List) return const [];

      var recoveredAnyJob = false;
      final jobs = payload
          .whereType<Map>()
          .map((item) => DownloadJob.fromJson(Map<String, dynamic>.from(item)))
          .whereType<DownloadJob>()
          .map((job) {
            final recovered = recoverRestoredQueueJob(job);
            if (!identical(recovered, job)) recoveredAnyJob = true;
            return recovered;
          })
          .toList(growable: false);
      if (recoveredAnyJob) {
        await save(jobs);
      }
      return jobs;
    } on FormatException {
      return const [];
    } on FileSystemException {
      return const [];
    }
  }

  Future<void> save(List<DownloadJob> jobs) async {
    final saveOperation = _saveTail.then((_) => _saveNow(jobs));
    _saveTail = saveOperation.catchError((_) {});
    return saveOperation;
  }

  Future<void> _saveNow(List<DownloadJob> jobs) async {
    final file = await _queueFile();
    await file.parent.create(recursive: true);

    final tempFile = File('${file.path}.tmp');
    const encoder = JsonEncoder.withIndent('  ');
    await tempFile.writeAsString(
      encoder.convert(jobs.map((job) => job.toJson()).toList()),
      flush: true,
    );

    if (await file.exists()) {
      try {
        await file.delete();
      } on PathNotFoundException {
        // A concurrent save or external cleanup may remove the file between
        // exists() and delete(). The temp file below still has the full state.
      }
    }
    await tempFile.rename(file.path);
  }

  Future<File> _queueFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }
}

DownloadJob recoverRestoredQueueJob(DownloadJob job) {
  if (job.status == DownloadStatus.downloading) {
    return _recoverInterruptedQueueJob(
      job,
      logLine: 'Download interrupted when the app closed.',
    );
  }
  if (job.status == DownloadStatus.queued) {
    return _recoverInterruptedQueueJob(
      job,
      logLine: 'Queued download interrupted when the app closed.',
    );
  }
  if (job.status == DownloadStatus.analyzing) {
    return job
        .appendLog('Analysis interrupted when the app closed.')
        .copyWith(
          status: DownloadStatus.failed,
          progress: 0,
          eta: 'Analysis interrupted',
          error: 'Analysis was interrupted when the app closed.',
        );
  }

  final localFileRecoveredJob = reconcileLocalQueueJobFiles(job);
  final childRecovery = _recoverRestoredQueueChildren(
    localFileRecoveredJob.children,
  );
  final jobWithRecoveredChildren = childRecovery.recoveredAny
      ? localFileRecoveredJob
            .copyWith(children: childRecovery.children)
            .appendLog('Child download state recovered after the app closed.')
      : localFileRecoveredJob;
  final reconciledJob = childRecovery.recoveredAny
      ? _recoverParentAfterChildRecovery(jobWithRecoveredChildren)
      : jobWithRecoveredChildren;

  return reconciledJob;
}

DownloadJob _recoverInterruptedQueueJob(
  DownloadJob job, {
  required String logLine,
}) {
  final childRecovery = _recoverRestoredQueueChildren(job.children);
  final hasManualSegments = job.children.any(
    (child) => child.kind == DownloadItemKind.manualSegment,
  );
  final recovered = job
      .copyWith(
        status: DownloadStatus.ready,
        progress: 0,
        eta: 'Interrupted',
        error: null,
        children: childRecovery.children,
        clearDownloadedFilePath: !hasManualSegments,
        clearDownloadedFileSize: !hasManualSegments,
        clearCompletedAt: true,
      )
      .appendLog(logLine);

  if (job.children.isEmpty) return recovered;

  return _recoverParentAfterChildRecovery(recovered);
}

DownloadJob reconcileLocalQueueJobFiles(DownloadJob job) {
  final childRecovery = _reconcileLocalQueueChildren(job);
  final jobWithRecoveredChildren = childRecovery.recoveredAny
      ? job
            .copyWith(children: childRecovery.children)
            .appendLog('Local child files reconciled from disk.')
      : job;
  final childRecoveredJob = childRecovery.recoveredAny
      ? _recoverParentAfterChildRecovery(jobWithRecoveredChildren)
      : jobWithRecoveredChildren;

  final parentRecoveredJob = _reconcileLocalQueueParentFile(childRecoveredJob);

  final hasManualSegments = job.children.any(
    (child) => child.kind == DownloadItemKind.manualSegment,
  );
  if (!hasManualSegments) return parentRecoveredJob;

  final splitSourceExists = _pathExists(
    parentRecoveredJob.splitEditorSourcePath,
  );
  if (splitSourceExists) {
    return _recoverParentAfterChildRecovery(parentRecoveredJob);
  }

  final downloadedFileExists = _pathExists(
    parentRecoveredJob.downloadedFilePath,
  );
  final remainingChildren = parentRecoveredJob.children
      .where((child) => child.kind != DownloadItemKind.manualSegment)
      .toList(growable: false);
  final shouldResetForDownload = !downloadedFileExists;

  return parentRecoveredJob
      .copyWith(
        status: shouldResetForDownload
            ? DownloadStatus.ready
            : parentRecoveredJob.status,
        progress: shouldResetForDownload ? 0 : parentRecoveredJob.progress,
        eta: shouldResetForDownload
            ? 'Ready to download'
            : parentRecoveredJob.eta,
        error: null,
        children: remainingChildren,
        isExpanded: remainingChildren.isNotEmpty && job.isExpanded,
        clearSplitPlan: true,
        clearSplitSourceFilePath: true,
        clearDownloadedFilePath: !downloadedFileExists,
        clearDownloadedFileSize: !downloadedFileExists,
        clearCompletedAt: !downloadedFileExists,
        clearOutputPath: shouldResetForDownload && remainingChildren.isEmpty,
      )
      .appendLog(
        'Split export plan removed because the source audio file is missing.',
      );
}

DownloadJob _reconcileLocalQueueParentFile(DownloadJob job) {
  if (job.children.isNotEmpty) return job;

  final fileExists = _pathExists(job.downloadedFilePath);
  if (fileExists) {
    if (job.status == DownloadStatus.complete && job.progress == 1) {
      return job;
    }

    return job.copyWith(
      status: DownloadStatus.complete,
      progress: 1,
      eta: 'Complete',
      error: null,
      clearCompletedAt: false,
    );
  }

  if (job.downloadedFilePath == null && job.status != DownloadStatus.complete) {
    return job;
  }

  return job
      .copyWith(
        status: DownloadStatus.ready,
        progress: 0,
        eta: 'Ready to download',
        error: null,
        clearDownloadedFilePath: true,
        clearDownloadedFileSize: true,
        clearCompletedAt: true,
        clearOutputPath: !_pathExists(job.outputPath),
      )
      .appendLog('Local downloaded file was missing and state was reset.');
}

({List<DownloadItem> children, bool recoveredAny}) _reconcileLocalQueueChildren(
  DownloadJob job,
) {
  var recoveredAny = false;
  final children = job.children;
  final recoveredChildren = [
    for (final child in children)
      () {
        final detectedOutput = _detectedChildOutputPath(job, child);
        final outputExists = detectedOutput != null;
        if (outputExists &&
            (child.status != DownloadStatus.complete ||
                child.downloadedFilePath != detectedOutput ||
                child.downloadedFileSize == null)) {
          recoveredAny = true;
          return child.copyWith(
            status: DownloadStatus.complete,
            progress: 1,
            error: null,
            outputPath: child.outputPath ?? job.outputPath,
            downloadedFilePath: detectedOutput,
            downloadedFileSize: _fileSizeSync(detectedOutput),
          );
        }

        if (!outputExists &&
            child.status == DownloadStatus.complete &&
            _childHadOutputPath(child)) {
          recoveredAny = true;
          return child.copyWith(
            status: DownloadStatus.ready,
            progress: 0,
            clearError: true,
            clearOutputPath: true,
            clearDownloadedFilePath: true,
            clearDownloadedFileSize: true,
            clearStartedAt: true,
            clearCompletedAt: true,
          );
        }

        return child;
      }(),
  ];

  return (children: recoveredChildren, recoveredAny: recoveredAny);
}

String? _detectedChildOutputPath(DownloadJob job, DownloadItem child) {
  if (child.kind != DownloadItemKind.manualSegment) {
    return _pathExists(child.bestOutputPath) ? child.bestOutputPath : null;
  }

  if (_pathIsFile(child.downloadedFilePath)) {
    return child.downloadedFilePath;
  }

  final expectedPath = _expectedManualSegmentPath(job, child);
  if (_pathIsFile(expectedPath)) return expectedPath;

  return _findManualSegmentPathByTitle(job, child);
}

bool _childHadOutputPath(DownloadItem child) {
  return child.downloadedFilePath != null || child.outputPath != null;
}

String? _expectedManualSegmentPath(DownloadJob job, DownloadItem child) {
  final directory = child.outputPath ?? job.outputPath;
  if (directory == null || directory.trim().isEmpty) return null;

  final manualChildren = job.children
      .where((candidate) => candidate.kind == DownloadItemKind.manualSegment)
      .toList(growable: false);
  final selectedManualChildren = manualChildren
      .where((candidate) => candidate.isSelected)
      .toList(growable: false);
  final indexedChildren =
      selectedManualChildren.any((candidate) => candidate.id == child.id)
      ? selectedManualChildren
      : manualChildren;
  final index = indexedChildren.indexWhere(
    (candidate) => candidate.id == child.id,
  );
  if (index == -1) return null;

  final separator = Platform.pathSeparator;
  final normalizedDirectory = directory.endsWith(separator)
      ? directory.substring(0, directory.length - 1)
      : directory;
  final prefix = (index + 1).toString().padLeft(2, '0');
  return '$normalizedDirectory$separator$prefix - ${_safePathName(child.title)}.mp3';
}

String? _findManualSegmentPathByTitle(DownloadJob job, DownloadItem child) {
  final directory = child.outputPath ?? job.outputPath;
  if (directory == null || directory.trim().isEmpty) return null;
  final folder = Directory(directory);
  if (!folder.existsSync()) return null;

  final expectedSuffix = ' - ${_safePathName(child.title)}.mp3';
  try {
    for (final entity in folder.listSync(followLinks: false)) {
      if (entity is! File) continue;
      final name = _fileNameFromPath(entity.path);
      if (name.endsWith(expectedSuffix)) return entity.path;
    }
  } on FileSystemException {
    return null;
  }
  return null;
}

String _fileNameFromPath(String path) {
  final separator = Platform.pathSeparator;
  final index = path.lastIndexOf(separator);
  return index == -1 ? path : path.substring(index + 1);
}

String _safePathName(String value) {
  final sanitized = value
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final fallback = sanitized.isEmpty ? 'Track' : sanitized;
  return fallback.length <= 80 ? fallback : fallback.substring(0, 80).trim();
}

({List<DownloadItem> children, bool recoveredAny})
_recoverRestoredQueueChildren(List<DownloadItem> children) {
  var recoveredAny = false;
  final recoveredChildren = [
    for (final child in children)
      switch (child.status) {
        DownloadStatus.complete
            when child.kind == DownloadItemKind.manualSegment &&
                !_pathExists(child.downloadedFilePath) =>
          () {
            recoveredAny = true;
            return child.copyWith(
              status: DownloadStatus.ready,
              progress: 0,
              clearError: true,
              clearOutputPath: true,
              clearDownloadedFilePath: true,
              clearDownloadedFileSize: true,
              clearStartedAt: true,
              clearCompletedAt: true,
            );
          }(),
        DownloadStatus.downloading || DownloadStatus.queued => () {
          recoveredAny = true;
          return child.copyWith(
            status: DownloadStatus.ready,
            progress: 0,
            error: null,
            clearOutputPath: true,
            clearDownloadedFilePath: true,
            clearDownloadedFileSize: true,
            clearStartedAt: true,
            clearCompletedAt: true,
          );
        }(),
        DownloadStatus.analyzing => () {
          recoveredAny = true;
          return child.copyWith(
            status: DownloadStatus.failed,
            progress: 0,
            error: 'Analysis was interrupted when the app closed.',
            clearStartedAt: true,
            clearCompletedAt: true,
          );
        }(),
        _ => child,
      },
  ];

  return (children: recoveredChildren, recoveredAny: recoveredAny);
}

DownloadJob _recoverParentAfterChildRecovery(DownloadJob job) {
  if (job.children.isEmpty) return job;

  final manualChildren = job.children
      .where((child) => child.kind == DownloadItemKind.manualSegment)
      .toList(growable: false);
  final candidateChildren = manualChildren.isEmpty
      ? job.children
      : manualChildren;
  final selectedChildren = candidateChildren
      .where((child) => child.isSelected)
      .toList(growable: false);
  final countableChildren = selectedChildren.isEmpty
      ? candidateChildren
      : selectedChildren;
  final completedCount = countableChildren
      .where(
        (child) =>
            child.status == DownloadStatus.complete &&
            _detectedChildOutputPath(job, child) != null,
      )
      .length;
  final totalCount = countableChildren.length;
  if (totalCount == 0) return job;

  final isSplitExport = manualChildren.isNotEmpty;
  final failedCount = countableChildren
      .where((child) => child.status == DownloadStatus.failed)
      .length;
  final hasAnyVerifiedOutput = job.children.any(
    (child) => _detectedChildOutputPath(job, child) != null,
  );

  if (completedCount == totalCount) {
    return job.copyWith(
      status: DownloadStatus.complete,
      progress: 1,
      eta: 'Complete',
      error: null,
    );
  }

  if (job.status == DownloadStatus.failed && failedCount > 0) {
    return job.copyWith(
      progress: completedCount / totalCount,
      clearDownloadedFilePath: !isSplitExport,
      clearDownloadedFileSize: !isSplitExport,
      clearCompletedAt: true,
    );
  }

  return job.copyWith(
    status: DownloadStatus.ready,
    progress: completedCount / totalCount,
    eta: _childRecoveryEta(
      completedCount: completedCount,
      totalCount: totalCount,
      isSplitExport: isSplitExport,
    ),
    error: null,
    clearOutputPath: !hasAnyVerifiedOutput && !_pathExists(job.outputPath),
    clearDownloadedFilePath: !isSplitExport,
    clearDownloadedFileSize: !isSplitExport,
    clearCompletedAt: true,
  );
}

String _childRecoveryEta({
  required int completedCount,
  required int totalCount,
  required bool isSplitExport,
}) {
  if (completedCount == 0) {
    return isSplitExport ? 'Ready to export' : 'Ready to download';
  }

  final noun = isSplitExport ? 'exported' : 'downloaded';
  return '$completedCount of $totalCount $noun';
}

bool _pathExists(String? path) {
  if (path == null || path.trim().isEmpty) return false;
  return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
}

bool _pathIsFile(String? path) {
  if (path == null || path.trim().isEmpty) return false;
  return FileSystemEntity.typeSync(path) == FileSystemEntityType.file;
}

int? _fileSizeSync(String? path) {
  if (!_pathIsFile(path)) return null;
  try {
    return File(path!).lengthSync();
  } on FileSystemException {
    return null;
  }
}
