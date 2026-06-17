import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:yt_dlp_desktop/models/download_models.dart';
import 'package:yt_dlp_desktop/services/queue/queue_repository.dart';

void main() {
  test('serializes overlapping saves when queue file is missing', () async {
    final directory = Directory.systemTemp.createTempSync(
      'fetchdeck_queue_repository_test_',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    PathProviderPlatform.instance = _FakePathProviderPlatform(directory.path);

    final repository = const QueueRepository();

    await Future.wait([
      for (var index = 0; index < 8; index += 1)
        repository.save([
          _job(
            DownloadStatus.ready,
          ).copyWith(title: 'Queued $index', eta: 'Ready $index'),
        ]),
    ]);

    final restored = await repository.load();
    expect(restored, hasLength(1));
    expect(restored.single.title, startsWith('Queued '));
  });

  test('recovers downloading jobs as ready after restart', () {
    final recovered = recoverRestoredQueueJob(
      _job(DownloadStatus.downloading).copyWith(
        progress: 0.5,
        eta: '50%',
        outputPath: '/downloads',
        downloadedFilePath: '/downloads/partial.mp3',
        downloadedFileSize: 1024,
        completedAt: DateTime.utc(2026, 6, 12),
      ),
    );

    expect(recovered.status, DownloadStatus.ready);
    expect(recovered.progress, 0);
    expect(recovered.eta, 'Interrupted');
    expect(recovered.error, isNull);
    expect(recovered.downloadedFilePath, isNull);
    expect(recovered.downloadedFileSize, isNull);
    expect(recovered.completedAt, isNull);
    expect(
      recovered.logLines,
      contains('Download interrupted when the app closed.'),
    );
  });

  test('recovers queued jobs as ready after restart', () {
    final recovered = recoverRestoredQueueJob(_job(DownloadStatus.queued));

    expect(recovered.status, DownloadStatus.ready);
    expect(recovered.progress, 0);
    expect(recovered.eta, 'Interrupted');
    expect(
      recovered.logLines,
      contains('Queued download interrupted when the app closed.'),
    );
  });

  test('recovers analyzing jobs as failed after restart', () {
    final recovered = recoverRestoredQueueJob(_job(DownloadStatus.analyzing));

    expect(recovered.status, DownloadStatus.failed);
    expect(recovered.progress, 0);
    expect(recovered.eta, 'Analysis interrupted');
    expect(recovered.error, 'Analysis was interrupted when the app closed.');
    expect(
      recovered.logLines,
      contains('Analysis interrupted when the app closed.'),
    );
  });

  test('resets completed jobs without a verifiable local file', () {
    final recovered = recoverRestoredQueueJob(
      _job(DownloadStatus.complete).copyWith(
        progress: 1,
        eta: 'Complete',
        completedAt: DateTime.utc(2026, 6, 12),
      ),
    );

    expect(recovered.status, DownloadStatus.ready);
    expect(recovered.progress, 0);
    expect(recovered.eta, 'Ready to download');
    expect(recovered.completedAt, isNull);
  });

  test('resets completed single-file jobs when local file is missing', () {
    final recovered = recoverRestoredQueueJob(
      _job(DownloadStatus.complete).copyWith(
        progress: 1,
        eta: 'Complete',
        outputPath: '/downloads/Missing Single',
        downloadedFilePath: '/downloads/Missing Single/source.mp3',
        downloadedFileSize: 1024,
        completedAt: DateTime.utc(2026, 6, 12),
      ),
    );

    expect(recovered.status, DownloadStatus.ready);
    expect(recovered.progress, 0);
    expect(recovered.eta, 'Ready to download');
    expect(recovered.downloadedFilePath, isNull);
    expect(recovered.downloadedFileSize, isNull);
    expect(recovered.completedAt, isNull);
  });

  test('keeps completed single-file jobs when local file exists', () {
    final tempDirectory = Directory.systemTemp.createTempSync(
      'fetchdeck_queue_repository_test_',
    );
    addTearDown(() => tempDirectory.deleteSync(recursive: true));
    final downloadedFile = File('${tempDirectory.path}/source.mp3')
      ..writeAsStringSync('audio');

    final recovered = recoverRestoredQueueJob(
      _job(DownloadStatus.ready).copyWith(
        progress: 0,
        eta: 'Ready',
        downloadedFilePath: downloadedFile.path,
      ),
    );

    expect(recovered.status, DownloadStatus.complete);
    expect(recovered.progress, 1);
    expect(recovered.eta, 'Complete');
    expect(recovered.downloadedFilePath, downloadedFile.path);
  });

  test('reconciles playlist children from local files', () {
    final tempDirectory = Directory.systemTemp.createTempSync(
      'fetchdeck_queue_repository_test_',
    );
    addTearDown(() => tempDirectory.deleteSync(recursive: true));
    final existingFile = File('${tempDirectory.path}/One.mp3')
      ..writeAsStringSync('audio');

    final recovered = recoverRestoredQueueJob(
      _job(DownloadStatus.complete).copyWith(
        progress: 1,
        eta: 'Complete',
        outputPath: tempDirectory.path,
        completedAt: DateTime.utc(2026, 6, 12),
        children: [
          DownloadItem(
            id: 'entry:1',
            kind: DownloadItemKind.playlistEntry,
            title: 'One',
            status: DownloadStatus.ready,
            progress: 0,
            downloadedFilePath: existingFile.path,
          ),
          const DownloadItem(
            id: 'entry:2',
            kind: DownloadItemKind.playlistEntry,
            title: 'Two',
            status: DownloadStatus.complete,
            progress: 1,
            downloadedFilePath: '/downloads/Missing Playlist/Two.mp3',
            downloadedFileSize: 1024,
          ),
        ],
      ),
    );

    expect(recovered.status, DownloadStatus.ready);
    expect(recovered.progress, 0.5);
    expect(recovered.eta, '1 of 2 downloaded');
    expect(recovered.completedAt, isNull);
    expect(recovered.children.first.status, DownloadStatus.complete);
    expect(recovered.children.first.progress, 1);
    expect(recovered.children.last.status, DownloadStatus.ready);
    expect(recovered.children.last.progress, 0);
    expect(recovered.children.last.downloadedFilePath, isNull);
    expect(recovered.children.last.downloadedFileSize, isNull);
  });

  test('recovers active parent and child rows after restart', () {
    final tempDirectory = Directory.systemTemp.createTempSync(
      'fetchdeck_queue_repository_test_',
    );
    addTearDown(() => tempDirectory.deleteSync(recursive: true));
    final existingFile = File('${tempDirectory.path}/One.mp3')
      ..writeAsStringSync('audio');

    final recovered = recoverRestoredQueueJob(
      _job(DownloadStatus.downloading).copyWith(
        progress: 0.6,
        eta: 'Downloading 2 of 3',
        outputPath: tempDirectory.path,
        children: [
          DownloadItem(
            id: 'entry:1',
            kind: DownloadItemKind.playlistEntry,
            title: 'One',
            status: DownloadStatus.complete,
            progress: 1,
            downloadedFilePath: existingFile.path,
          ),
          const DownloadItem(
            id: 'entry:2',
            kind: DownloadItemKind.playlistEntry,
            title: 'Two',
            status: DownloadStatus.downloading,
            progress: 0.5,
            downloadedFilePath: '/downloads/partial.mp3',
          ),
        ],
      ),
    );

    expect(recovered.status, DownloadStatus.ready);
    expect(recovered.progress, 0.5);
    expect(recovered.eta, '1 of 2 downloaded');
    expect(recovered.children.first.status, DownloadStatus.complete);
    expect(recovered.children.last.status, DownloadStatus.ready);
    expect(recovered.children.last.progress, 0);
    expect(recovered.children.last.downloadedFilePath, isNull);
  });

  test('recovers interrupted child rows after restart', () {
    final tempDirectory = Directory.systemTemp.createTempSync(
      'fetchdeck_queue_repository_test_',
    );
    addTearDown(() => tempDirectory.deleteSync(recursive: true));
    final sourceFile = File('${tempDirectory.path}/source.mp3')
      ..writeAsStringSync('audio');
    final completedFile = File('${tempDirectory.path}/Opening.mp3')
      ..writeAsStringSync('audio');

    final recovered = recoverRestoredQueueJob(
      _job(DownloadStatus.complete).copyWith(
        downloadedFilePath: sourceFile.path,
        children: [
          DownloadItem(
            id: 'segment:1',
            kind: DownloadItemKind.manualSegment,
            title: 'Opening',
            status: DownloadStatus.complete,
            progress: 1,
            downloadedFilePath: completedFile.path,
          ),
          DownloadItem(
            id: 'segment:2',
            kind: DownloadItemKind.manualSegment,
            title: 'Closing',
            status: DownloadStatus.downloading,
            progress: 0.5,
            outputPath: '/downloads',
            downloadedFilePath: '/downloads/partial.mp3',
            downloadedFileSize: 512,
            startedAt: DateTime.utc(2026, 6, 12, 10),
            completedAt: DateTime.utc(2026, 6, 12, 11),
          ),
          const DownloadItem(
            id: 'entry:3',
            kind: DownloadItemKind.playlistEntry,
            title: 'Queued',
            status: DownloadStatus.queued,
            progress: 0,
          ),
        ],
      ),
    );

    expect(recovered.status, DownloadStatus.ready);
    expect(recovered.progress, 0.5);
    expect(recovered.eta, '1 of 2 exported');
    expect(recovered.children[0].status, DownloadStatus.complete);
    expect(recovered.children[0].downloadedFilePath, completedFile.path);
    expect(recovered.children[1].status, DownloadStatus.ready);
    expect(recovered.children[1].progress, 0);
    expect(recovered.children[1].outputPath, isNull);
    expect(recovered.children[1].downloadedFilePath, isNull);
    expect(recovered.children[1].downloadedFileSize, isNull);
    expect(recovered.children[1].startedAt, isNull);
    expect(recovered.children[1].completedAt, isNull);
    expect(recovered.children[2].status, DownloadStatus.ready);
    expect(
      recovered.logLines,
      contains('Child download state recovered after the app closed.'),
    );
  });

  test('recovers missing completed manual segment files as ready', () {
    final tempDirectory = Directory.systemTemp.createTempSync(
      'fetchdeck_queue_repository_test_',
    );
    addTearDown(() => tempDirectory.deleteSync(recursive: true));
    final sourceFile = File('${tempDirectory.path}/source.mp3')
      ..writeAsStringSync('audio');

    final recovered = recoverRestoredQueueJob(
      _job(DownloadStatus.complete).copyWith(
        progress: 1,
        eta: 'Complete',
        outputPath: '/downloads/Missing Mix',
        downloadedFilePath: sourceFile.path,
        completedAt: DateTime.utc(2026, 6, 12),
        children: const [
          DownloadItem(
            id: 'segment:1',
            kind: DownloadItemKind.manualSegment,
            title: 'Opening',
            status: DownloadStatus.complete,
            progress: 1,
            downloadedFilePath: '/downloads/Missing Mix/01 - Opening.mp3',
            downloadedFileSize: 1024,
            isSelected: true,
          ),
        ],
      ),
    );

    expect(recovered.status, DownloadStatus.ready);
    expect(recovered.progress, 0);
    expect(recovered.eta, 'Ready to export');
    expect(recovered.outputPath, isNull);
    expect(recovered.completedAt, isNull);
    expect(recovered.children.single.status, DownloadStatus.ready);
    expect(recovered.children.single.progress, 0);
    expect(recovered.children.single.downloadedFilePath, isNull);
    expect(recovered.children.single.downloadedFileSize, isNull);
  });

  test('detects exported manual segment files from the output folder', () {
    final tempDirectory = Directory.systemTemp.createTempSync(
      'fetchdeck_queue_repository_test_',
    );
    addTearDown(() => tempDirectory.deleteSync(recursive: true));
    final sourceFile = File('${tempDirectory.path}/source.mp3')
      ..writeAsStringSync('audio');
    final exportedFile = File('${tempDirectory.path}/01 - Opening.mp3')
      ..writeAsStringSync('exported audio');

    final recovered = recoverRestoredQueueJob(
      _job(DownloadStatus.ready).copyWith(
        outputPath: tempDirectory.path,
        downloadedFilePath: sourceFile.path,
        children: [
          DownloadItem(
            id: 'segment:1',
            kind: DownloadItemKind.manualSegment,
            title: 'Opening',
            status: DownloadStatus.ready,
            progress: 0,
            outputPath: tempDirectory.path,
            isSelected: true,
          ),
          DownloadItem(
            id: 'segment:2',
            kind: DownloadItemKind.manualSegment,
            title: 'Closing',
            status: DownloadStatus.ready,
            progress: 0,
            outputPath: tempDirectory.path,
            isSelected: true,
          ),
        ],
      ),
    );

    expect(recovered.status, DownloadStatus.ready);
    expect(recovered.progress, 0.5);
    expect(recovered.eta, '1 of 2 exported');
    expect(recovered.children.first.status, DownloadStatus.complete);
    expect(recovered.children.first.progress, 1);
    expect(recovered.children.first.downloadedFilePath, exportedFile.path);
    expect(
      recovered.children.first.downloadedFileSize,
      exportedFile.lengthSync(),
    );
    expect(recovered.children.last.status, DownloadStatus.ready);
    expect(recovered.children.last.downloadedFilePath, isNull);
  });

  test('detects manual segment files with percent signs in names', () {
    final tempDirectory = Directory.systemTemp.createTempSync(
      'fetchdeck_queue_repository_test_',
    );
    addTearDown(() => tempDirectory.deleteSync(recursive: true));
    final sourceFile = File('${tempDirectory.path}/source.mp3')
      ..writeAsStringSync('audio');
    final exportedFile = File('${tempDirectory.path}/01 - 100% Human.mp3')
      ..writeAsStringSync('exported audio');

    final recovered = recoverRestoredQueueJob(
      _job(DownloadStatus.ready).copyWith(
        outputPath: tempDirectory.path,
        downloadedFilePath: sourceFile.path,
        children: [
          DownloadItem(
            id: 'segment:1',
            kind: DownloadItemKind.manualSegment,
            title: '100% Human',
            status: DownloadStatus.ready,
            progress: 0,
            outputPath: tempDirectory.path,
            isSelected: true,
          ),
        ],
      ),
    );

    expect(recovered.children.single.status, DownloadStatus.complete);
    expect(recovered.children.single.downloadedFilePath, exportedFile.path);
  });

  test('does not treat manual segment output folder as an exported file', () {
    final tempDirectory = Directory.systemTemp.createTempSync(
      'fetchdeck_queue_repository_test_',
    );
    addTearDown(() => tempDirectory.deleteSync(recursive: true));
    final sourceFile = File('${tempDirectory.path}/source.mp3')
      ..writeAsStringSync('audio');

    final recovered = recoverRestoredQueueJob(
      _job(DownloadStatus.ready).copyWith(
        outputPath: tempDirectory.path,
        downloadedFilePath: sourceFile.path,
        children: [
          DownloadItem(
            id: 'segment:1',
            kind: DownloadItemKind.manualSegment,
            title: 'Opening',
            status: DownloadStatus.ready,
            progress: 0,
            outputPath: tempDirectory.path,
            isSelected: true,
          ),
        ],
      ),
    );

    expect(recovered.status, DownloadStatus.ready);
    expect(recovered.progress, 0);
    expect(recovered.eta, 'Ready to export');
    expect(recovered.children.single.status, DownloadStatus.ready);
    expect(recovered.children.single.downloadedFilePath, isNull);
  });

  test('removes split export plan when source audio file is missing', () {
    final recovered = recoverRestoredQueueJob(
      _job(DownloadStatus.complete).copyWith(
        progress: 1,
        eta: 'Complete',
        downloadedFilePath: '/downloads/Missing Mix/source.mp3',
        splitSourceFilePath: '/downloads/Missing Mix/source.mp3',
        splitPlan: _splitPlan('/downloads/Missing Mix/source.mp3'),
        isExpanded: true,
        children: const [
          DownloadItem(
            id: 'segment:1',
            kind: DownloadItemKind.manualSegment,
            title: 'Track 01',
            status: DownloadStatus.ready,
            progress: 0,
            isSelected: true,
          ),
          DownloadItem(
            id: 'entry:1',
            kind: DownloadItemKind.playlistEntry,
            title: 'Playlist item',
            status: DownloadStatus.ready,
            progress: 0,
          ),
        ],
      ),
    );

    expect(recovered.status, DownloadStatus.ready);
    expect(recovered.progress, 0);
    expect(recovered.downloadedFilePath, isNull);
    expect(recovered.splitSourceFilePath, isNull);
    expect(recovered.splitPlan, isNull);
    expect(
      recovered.children.any(
        (child) => child.kind == DownloadItemKind.manualSegment,
      ),
      isFalse,
    );
    expect(recovered.children.single.kind, DownloadItemKind.playlistEntry);
    expect(recovered.isExpanded, isTrue);
  });

  test('recovers interrupted child analysis as failed', () {
    final recovered = recoverRestoredQueueJob(
      _job(DownloadStatus.ready).copyWith(
        children: const [
          DownloadItem(
            id: 'entry:1',
            kind: DownloadItemKind.playlistEntry,
            title: 'Analyzing',
            status: DownloadStatus.analyzing,
            progress: 0.4,
          ),
        ],
      ),
    );

    expect(recovered.children.single.status, DownloadStatus.failed);
    expect(recovered.children.single.progress, 0);
    expect(
      recovered.children.single.error,
      'Analysis was interrupted when the app closed.',
    );
  });
}

class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform(this.applicationSupportPath);

  final String applicationSupportPath;

  @override
  Future<String?> getApplicationSupportPath() async => applicationSupportPath;
}

DownloadJob _job(DownloadStatus status) {
  return DownloadJob(
    id: 'job-${status.name}',
    url: 'https://example.com/${status.name}',
    title: status.label,
    source: 'example.com',
    preset: PresetDefinition.defaultPreset,
    status: status,
    progress: 0,
    eta: status.label,
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
