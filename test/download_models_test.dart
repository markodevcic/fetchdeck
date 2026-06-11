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
      mediaInfo: const MediaInfo(
        title: 'Example Video',
        webpageUrl: 'https://example.com/video',
        extractor: 'Example',
        formatCount: 12,
        uploader: 'Uploader',
        thumbnail: 'https://example.com/thumb.jpg',
        duration: Duration(seconds: 90),
      ),
    );

    final restored = DownloadJob.fromJson(job.toJson());

    expect(restored, isNotNull);
    expect(restored!.id, job.id);
    expect(restored.preset, DownloadPreset.mp3_320.toDefinition());
    expect(restored.status, DownloadStatus.complete);
    expect(restored.mediaInfo?.duration, const Duration(seconds: 90));
    expect(restored.outputPath, '/tmp/Fetchdeck');
  });
}
