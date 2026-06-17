import 'package:flutter_test/flutter_test.dart';
import 'package:yt_dlp_desktop/services/ffmpeg/ffmpeg_silence_detection_service.dart';

void main() {
  test('builds ffmpeg silence detection arguments', () {
    expect(
      FfmpegSilenceDetectionService.buildArguments(
        sourceFilePath: '/tmp/source.mp3',
        noiseThreshold: '-35dB',
        minimumSilence: const Duration(milliseconds: 1200),
      ),
      [
        '-hide_banner',
        '-nostats',
        '-progress',
        'pipe:1',
        '-i',
        '/tmp/source.mp3',
        '-af',
        'silencedetect=noise=-35dB:d=1.200',
        '-f',
        'null',
        '-',
      ],
    );
  });

  test('parses ffmpeg progress output', () {
    expect(
      FfmpegSilenceProgressParser.parseLine(
        'out_time_ms=120000000',
        duration: const Duration(minutes: 4),
      ),
      0.5,
    );
    expect(
      FfmpegSilenceProgressParser.parseLine(
        'out_time=00:01:00.000000',
        duration: const Duration(minutes: 4),
      ),
      0.25,
    );
    expect(
      FfmpegSilenceProgressParser.parseLine(
        'progress=continue',
        duration: const Duration(minutes: 4),
      ),
      isNull,
    );
  });

  test('parses silence end timestamps as likely song starts', () {
    const output = '''
[silencedetect @ 0x1] silence_start: 12.40
[silencedetect @ 0x1] silence_end: 15.75 | silence_duration: 3.35
[silencedetect @ 0x1] silence_start: 122.00
[silencedetect @ 0x1] silence_end: 126.8 | silence_duration: 4.8
''';

    expect(FfmpegSilenceParser.parse(output), [
      const Duration(seconds: 15, milliseconds: 750),
      const Duration(seconds: 126, milliseconds: 800),
    ]);
  });
}
