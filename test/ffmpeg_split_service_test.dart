import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/services/ffmpeg/ffmpeg_split_service.dart';

void main() {
  test('builds mp3 split arguments with fade filters', () {
    final arguments = FfmpegSplitService.buildArguments(
      sourceFilePath: '/tmp/source.mp3',
      outputFilePath: '/tmp/out/01 - Song.mp3',
      title: 'Song',
      startTime: const Duration(minutes: 3, seconds: 12),
      duration: const Duration(minutes: 4),
      fadeDuration: const Duration(milliseconds: 250),
    );

    expect(arguments, [
      '-y',
      '-hide_banner',
      '-nostats',
      '-progress',
      'pipe:1',
      '-ss',
      '192.000',
      '-i',
      '/tmp/source.mp3',
      '-t',
      '240.000',
      '-vn',
      '-map_metadata',
      '-1',
      '-metadata',
      'title=Song',
      '-acodec',
      'libmp3lame',
      '-b:a',
      '320k',
      '-af',
      'afade=t=in:st=0:d=0.250,afade=t=out:st=239.750:d=0.250',
      '/tmp/out/01 - Song.mp3',
    ]);
  });

  test('parses ffmpeg progress output', () {
    expect(
      FfmpegProgressParser.parseLine(
        'out_time_ms=120000000',
        duration: const Duration(minutes: 4),
      ),
      0.5,
    );
    expect(
      FfmpegProgressParser.parseLine(
        'out_time=00:01:00.000000',
        duration: const Duration(minutes: 4),
      ),
      0.25,
    );
    expect(
      FfmpegProgressParser.parseLine(
        'progress=continue',
        duration: const Duration(minutes: 4),
      ),
      isNull,
    );
  });
}
