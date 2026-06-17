import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/models/download_models.dart';

void main() {
  test('download job round-trips through json', () {
    final job = DownloadJob(
      id: 'job-1',
      url: 'https://example.com/video',
      title: 'Example Video',
      source: 'Example',
      preset: DownloadPreset.mp3_320.toDefinition(),
      status: DownloadStatus.complete,
      progress: 1,
      eta: 'Complete',
      outputPath: '/tmp/Fetchdeck',
      downloadedFilePath: '/tmp/Fetchdeck/example.mp3',
      splitSourceFilePath: '/tmp/Fetchdeck/.fetchdeck/source/example.mp3',
      downloadedFileSize: 3145728,
      startedAt: DateTime.utc(2026, 6, 12, 10, 30),
      completedAt: DateTime.utc(2026, 6, 12, 10, 34),
      logLines: const ['Download started.', 'Download complete.'],
      isExpanded: true,
      splitPlan: SplitPlan(
        sourceFilePath: '/tmp/Fetchdeck/source.mp3',
        markers: const [
          SplitMarker(
            id: 'marker-0',
            position: Duration.zero,
            title: 'Opening Song',
          ),
          SplitMarker(
            id: 'marker-1',
            position: Duration(minutes: 4, seconds: 18),
            title: 'Amazing Grace',
          ),
        ],
        fadeDuration: const Duration(milliseconds: 250),
        appliedAt: DateTime.utc(2026, 6, 12, 10, 35),
      ),
      children: [
        DownloadItem(
          id: 'entry:abc123',
          kind: DownloadItemKind.playlistEntry,
          title: '1. Track One',
          url: 'https://example.com/watch?v=abc123',
          source: 'Example',
          thumbnail: 'https://example.com/track.jpg',
          duration: const Duration(minutes: 3),
          status: DownloadStatus.complete,
          progress: 1,
          outputPath: '/tmp/Fetchdeck/Track One',
          downloadedFilePath: '/tmp/Fetchdeck/Track One/track.mp3',
          downloadedFileSize: 1024,
          startedAt: DateTime.utc(2026, 6, 12, 10, 31),
          completedAt: DateTime.utc(2026, 6, 12, 10, 32),
        ),
        const DownloadItem(
          id: 'chapter:1',
          kind: DownloadItemKind.chapter,
          title: 'Intro',
          url: 'https://example.com/video',
          source: 'Example',
          duration: Duration(seconds: 20),
          startTime: Duration.zero,
          endTime: Duration(seconds: 20),
          status: DownloadStatus.ready,
          progress: 0,
          isSelected: false,
        ),
        const DownloadItem(
          id: 'segment:1',
          kind: DownloadItemKind.manualSegment,
          title: 'Amazing Grace',
          sourceFilePath: '/tmp/Fetchdeck/source.mp3',
          duration: Duration(minutes: 5, seconds: 24),
          startTime: Duration(minutes: 4, seconds: 18),
          endTime: Duration(minutes: 9, seconds: 42),
          fadeDuration: Duration(milliseconds: 250),
          status: DownloadStatus.ready,
          progress: 0,
        ),
      ],
      mediaInfo: const MediaInfo(
        title: 'Example Video',
        webpageUrl: 'https://example.com/video',
        extractor: 'Example',
        formatCount: 12,
        uploader: 'Uploader',
        thumbnail: 'https://example.com/thumb.jpg',
        duration: Duration(seconds: 90),
        entries: [
          MediaEntry(
            id: 'abc123',
            title: 'Track One',
            webpageUrl: 'https://example.com/watch?v=abc123',
            extractor: 'Example',
            duration: Duration(minutes: 3),
            playlistIndex: 1,
          ),
        ],
        chapters: [
          MediaChapter(
            title: 'Intro',
            startTime: Duration.zero,
            endTime: Duration(seconds: 20),
          ),
        ],
      ),
    );

    final restored = DownloadJob.fromJson(job.toJson());

    expect(restored, isNotNull);
    expect(restored!.id, job.id);
    expect(restored.preset, DownloadPreset.mp3_320.toDefinition());
    expect(restored.status, DownloadStatus.complete);
    expect(restored.mediaInfo?.duration, const Duration(seconds: 90));
    expect(restored.outputPath, '/tmp/Fetchdeck');
    expect(restored.downloadedFilePath, '/tmp/Fetchdeck/example.mp3');
    expect(
      restored.splitSourceFilePath,
      '/tmp/Fetchdeck/.fetchdeck/source/example.mp3',
    );
    expect(
      restored.splitEditorSourcePath,
      '/tmp/Fetchdeck/.fetchdeck/source/example.mp3',
    );
    expect(restored.downloadedFileSize, 3145728);
    expect(restored.bestOutputPath, '/tmp/Fetchdeck/example.mp3');
    expect(restored.startedAt, DateTime.utc(2026, 6, 12, 10, 30));
    expect(restored.completedAt, DateTime.utc(2026, 6, 12, 10, 34));
    expect(restored.logLines, ['Download started.', 'Download complete.']);
    expect(restored.isExpanded, isTrue);
    expect(restored.childCount, 3);
    expect(restored.selectedChildCount, 2);
    expect(restored.children.first.bestOutputPath, endsWith('track.mp3'));
    expect(restored.children[1].kind, DownloadItemKind.chapter);
    expect(restored.children[1].isSelected, isFalse);
    expect(restored.children.last.kind, DownloadItemKind.manualSegment);
    expect(restored.children.last.sourceFilePath, '/tmp/Fetchdeck/source.mp3');
    expect(
      restored.children.last.fadeDuration,
      const Duration(milliseconds: 250),
    );
    expect(restored.splitPlan?.sourceFilePath, '/tmp/Fetchdeck/source.mp3');
    expect(restored.splitPlan?.hasFade, isTrue);
    expect(restored.splitPlan?.markers.last.title, 'Amazing Grace');
    expect(
      restored.splitPlan?.markers.last.position,
      const Duration(minutes: 4, seconds: 18),
    );
    expect(restored.splitPlan?.appliedAt, DateTime.utc(2026, 6, 12, 10, 35));
    expect(restored.mediaInfo?.entries.single.title, 'Track One');
    expect(
      restored.mediaInfo?.chapters.single.duration,
      const Duration(seconds: 20),
    );
  });

  test('download job can clear split plan', () {
    final job = DownloadJob(
      id: 'job-1',
      url: 'https://example.com/video',
      title: 'Example Video',
      source: 'Example',
      preset: DownloadPreset.mp3_320.toDefinition(),
      status: DownloadStatus.ready,
      progress: 0,
      eta: 'Ready',
      splitPlan: SplitPlan(
        sourceFilePath: '/tmp/source.mp3',
        markers: const [
          SplitMarker(
            id: 'marker-0',
            position: Duration.zero,
            title: 'Track 01',
          ),
        ],
        fadeDuration: Duration.zero,
        appliedAt: DateTime.utc(2026, 6, 12),
      ),
    );

    expect(job.copyWith(clearSplitPlan: true).splitPlan, isNull);
  });

  test('download job appendLog keeps the newest bounded lines', () {
    var job = DownloadJob(
      id: 'job-1',
      url: 'https://example.com/video',
      title: 'Example Video',
      source: 'Example',
      preset: DownloadPreset.mp3_320.toDefinition(),
      status: DownloadStatus.ready,
      progress: 0,
      eta: 'Ready',
    );

    for (var index = 0; index < 90; index += 1) {
      job = job.appendLog('line $index');
    }

    expect(job.logLines, hasLength(80));
    expect(job.logLines.first, 'line 10');
    expect(job.logLines.last, 'line 89');
  });
}
